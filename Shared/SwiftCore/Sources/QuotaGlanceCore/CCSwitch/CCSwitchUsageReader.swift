import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

public enum CCSwitchUsageReaderError: LocalizedError, Equatable, Sendable {
    case databaseNotFound(String)
    case unableToOpen(String)
    case incompatibleDatabase
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .databaseNotFound(path):
            "cc-switch database not found at \(path)"
        case let .unableToOpen(message):
            "Unable to open cc-switch database: \(message)"
        case .incompatibleDatabase:
            "This database does not contain cc-switch request logs."
        case let .queryFailed(message):
            "Could not read cc-switch usage: \(message)"
        }
    }
}

/// Reads cc-switch's SQLite log with SQLite's read-only flag. This object has
/// no write statements, so opening it cannot alter cc-switch state.
public final class CCSwitchUsageReader: @unchecked Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func load(
        range: CCSwitchTimeRange,
        app: String? = nil,
        now: Date = .now
    ) throws -> CCSwitchUsageDashboard {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CCSwitchUsageReaderError.databaseNotFound(databaseURL.path)
        }
        let connection = try Connection(url: databaseURL)
        defer { connection.close() }

        guard try connection.tableExists("proxy_request_logs") else {
            throw CCSwitchUsageReaderError.incompatibleDatabase
        }

        let windowStart = now.timeIntervalSince1970 - range.seconds
        let predicate = LogPredicate(startedAt: windowStart, app: app)
        let summary = try summary(connection, predicate: predicate)
        let timeline = try timeline(
            connection,
            predicate: predicate,
            range: range,
            windowStart: windowStart
        )
        return CCSwitchUsageDashboard(
            databaseURL: databaseURL,
            range: range,
            selectedApp: app,
            capturedAt: now,
            summary: summary,
            timeline: timeline,
            applications: try breakdown(connection, predicate: predicate, kind: .application),
            providers: try breakdown(connection, predicate: predicate, kind: .provider),
            models: try breakdown(connection, predicate: predicate, kind: .model),
            failures: try failures(connection, predicate: predicate),
            recentRequests: try recentRequests(connection, predicate: predicate)
        )
    }
}

private struct LogPredicate {
    let startedAt: TimeInterval
    let app: String?

    var sql: String {
        if app == nil { return "r.created_at >= ?" }
        return "r.created_at >= ? AND r.app_type = ?"
    }

    func bind(_ statement: OpaquePointer?) {
        sqlite3_bind_double(statement, 1, startedAt)
        if let app {
            sqlite3_bind_text(statement, 2, app, -1, sqliteTransient)
        }
    }
}

private enum BreakdownKind {
    case application
    case provider
    case model

    var projection: String {
        switch self {
        case .application:
            "COALESCE(NULLIF(r.app_type, ''), 'Unknown') AS name, NULL AS detail"
        case .provider:
            "COALESCE(NULLIF(p.name, ''), NULLIF(r.provider_id, ''), 'Unknown') AS name, COALESCE(NULLIF(r.app_type, ''), 'Unknown') AS detail"
        case .model:
            "COALESCE(NULLIF(r.model, ''), 'Unknown') AS name, NULL AS detail"
        }
    }

    var groupBy: String {
        switch self {
        case .application: "COALESCE(NULLIF(r.app_type, ''), 'Unknown')"
        case .provider: "COALESCE(NULLIF(p.name, ''), NULLIF(r.provider_id, ''), 'Unknown'), COALESCE(NULLIF(r.app_type, ''), 'Unknown')"
        case .model: "COALESCE(NULLIF(r.model, ''), 'Unknown')"
        }
    }
}

private func summary(
    _ connection: Connection,
    predicate: LogPredicate
) throws -> CCSwitchUsageSummary {
    let sql = """
    SELECT COUNT(*),
      COALESCE(SUM(CASE WHEN r.status_code < 300 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN r.status_code >= 300 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(r.input_tokens), 0), COALESCE(SUM(r.output_tokens), 0),
      COALESCE(SUM(r.cache_read_tokens), 0), COALESCE(SUM(r.cache_creation_tokens), 0),
      COALESCE(SUM(CAST(r.total_cost_usd AS REAL)), 0),
      AVG(NULLIF(r.first_token_ms, 0))
    FROM proxy_request_logs r WHERE \(predicate.sql)
    """
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    predicate.bind(statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { throw connection.error }

    let latencies = try scalarDoubles(
        connection,
        sql: "SELECT r.latency_ms FROM proxy_request_logs r WHERE \(predicate.sql) AND r.latency_ms > 0 ORDER BY r.latency_ms",
        predicate: predicate
    )
    return CCSwitchUsageSummary(
        requests: Int(sqlite3_column_int64(statement, 0)),
        successfulRequests: Int(sqlite3_column_int64(statement, 1)),
        failedRequests: Int(sqlite3_column_int64(statement, 2)),
        inputTokens: sqlite3_column_int64(statement, 3),
        outputTokens: sqlite3_column_int64(statement, 4),
        cacheReadTokens: sqlite3_column_int64(statement, 5),
        cacheCreationTokens: sqlite3_column_int64(statement, 6),
        costUSD: decimal(statement, column: 7),
        medianLatencyMilliseconds: median(latencies),
        averageFirstTokenMilliseconds: nullableDouble(statement, column: 8)
    )
}

private func timeline(
    _ connection: Connection,
    predicate: LogPredicate,
    range: CCSwitchTimeRange,
    windowStart: TimeInterval
) throws -> [CCSwitchTimelinePoint] {
    let bucketCount = min(24, max(6, Int(range.seconds / 60)))
    let bucketSeconds = max(1, range.seconds / Double(bucketCount))
    let sql = """
    SELECT CAST((r.created_at - ?) / ? AS INTEGER),
      COALESCE(SUM(r.input_tokens), 0), COALESCE(SUM(r.output_tokens), 0),
      COALESCE(SUM(r.cache_read_tokens), 0), COUNT(*)
    FROM proxy_request_logs r
    WHERE \(predicate.sql)
    GROUP BY 1 ORDER BY 1
    """
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_double(statement, 1, windowStart)
    sqlite3_bind_double(statement, 2, bucketSeconds)
    sqlite3_bind_double(statement, 3, predicate.startedAt)
    if let app = predicate.app { sqlite3_bind_text(statement, 4, app, -1, sqliteTransient) }

    var results: [CCSwitchTimelinePoint] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let index = sqlite3_column_int64(statement, 0)
        results.append(CCSwitchTimelinePoint(
            startedAt: Date(timeIntervalSince1970: windowStart + Double(index) * bucketSeconds),
            inputTokens: sqlite3_column_int64(statement, 1),
            outputTokens: sqlite3_column_int64(statement, 2),
            cacheReadTokens: sqlite3_column_int64(statement, 3),
            requestCount: Int(sqlite3_column_int64(statement, 4))
        ))
    }
    guard sqlite3_errcode(connection.db) == SQLITE_OK || sqlite3_errcode(connection.db) == SQLITE_DONE else {
        throw connection.error
    }
    return results
}

private func breakdown(
    _ connection: Connection,
    predicate: LogPredicate,
    kind: BreakdownKind
) throws -> [CCSwitchBreakdownRow] {
    let sql = """
    SELECT \(kind.projection), COUNT(*),
      COALESCE(SUM(CASE WHEN r.status_code >= 300 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(r.input_tokens + r.output_tokens), 0),
      COALESCE(SUM(r.cache_read_tokens), 0),
      COALESCE(SUM(CAST(r.total_cost_usd AS REAL)), 0), AVG(NULLIF(r.latency_ms, 0))
    FROM proxy_request_logs r
    LEFT JOIN providers p ON r.provider_id = p.id AND r.app_type = p.app_type
    WHERE \(predicate.sql)
    GROUP BY \(kind.groupBy) ORDER BY 5 DESC, 3 DESC
    """
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    predicate.bind(statement)
    var rows: [CCSwitchBreakdownRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        rows.append(CCSwitchBreakdownRow(
            name: string(statement, column: 0) ?? "Unknown",
            detail: string(statement, column: 1),
            requests: Int(sqlite3_column_int64(statement, 2)),
            failures: Int(sqlite3_column_int64(statement, 3)),
            tokens: sqlite3_column_int64(statement, 4),
            cacheReadTokens: sqlite3_column_int64(statement, 5),
            costUSD: decimal(statement, column: 6),
            averageLatencyMilliseconds: nullableDouble(statement, column: 7)
        ))
    }
    return rows
}

private func failures(_ connection: Connection, predicate: LogPredicate) throws -> [CCSwitchFailure] {
    let sql = """
    SELECT r.status_code, COUNT(*), MIN(NULLIF(r.error_message, ''))
    FROM proxy_request_logs r WHERE \(predicate.sql) AND r.status_code >= 300
    GROUP BY r.status_code ORDER BY 2 DESC
    """
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    predicate.bind(statement)
    var rows: [CCSwitchFailure] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        rows.append(CCSwitchFailure(
            statusCode: Int(sqlite3_column_int64(statement, 0)),
            count: Int(sqlite3_column_int64(statement, 1)),
            sampleMessage: string(statement, column: 2)
        ))
    }
    return rows
}

private func recentRequests(_ connection: Connection, predicate: LogPredicate) throws -> [CCSwitchRecentRequest] {
    let sql = """
    SELECT r.created_at, COALESCE(NULLIF(r.app_type, ''), 'Unknown'),
      COALESCE(NULLIF(p.name, ''), NULLIF(r.provider_id, ''), 'Unknown'),
      COALESCE(NULLIF(r.model, ''), 'Unknown'), COALESCE(r.output_tokens, 0),
      NULLIF(r.latency_ms, 0), r.status_code
    FROM proxy_request_logs r
    LEFT JOIN providers p ON r.provider_id = p.id AND r.app_type = p.app_type
    WHERE \(predicate.sql) ORDER BY r.created_at DESC LIMIT 12
    """
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    predicate.bind(statement)
    var rows: [CCSwitchRecentRequest] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        rows.append(CCSwitchRecentRequest(
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
            app: string(statement, column: 1) ?? "Unknown",
            provider: string(statement, column: 2) ?? "Unknown",
            model: string(statement, column: 3) ?? "Unknown",
            outputTokens: sqlite3_column_int64(statement, 4),
            latencyMilliseconds: nullableDouble(statement, column: 5),
            statusCode: Int(sqlite3_column_int64(statement, 6))
        ))
    }
    return rows
}

private func scalarDoubles(
    _ connection: Connection,
    sql: String,
    predicate: LogPredicate
) throws -> [Double] {
    let statement = try connection.statement(sql)
    defer { sqlite3_finalize(statement) }
    predicate.bind(statement)
    var values: [Double] = []
    while sqlite3_step(statement) == SQLITE_ROW { values.append(sqlite3_column_double(statement, 0)) }
    return values
}

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let index = values.count / 2
    if values.count.isMultiple(of: 2) { return (values[index - 1] + values[index]) / 2 }
    return values[index]
}

private func string(_ statement: OpaquePointer?, column: Int32) -> String? {
    guard let text = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: text)
}

private func nullableDouble(_ statement: OpaquePointer?, column: Int32) -> Double? {
    sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
}

private func decimal(_ statement: OpaquePointer?, column: Int32) -> Decimal {
    Decimal(string: String(sqlite3_column_double(statement, column)), locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

private final class Connection {
    private(set) var db: OpaquePointer?

    init(url: URL) throws {
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            sqlite3_close(db)
            throw CCSwitchUsageReaderError.unableToOpen(message)
        }
    }

    func close() { sqlite3_close(db); db = nil }

    func statement(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error }
        return statement
    }

    func tableExists(_ name: String) throws -> Bool {
        let statement = try statement("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    var error: CCSwitchUsageReaderError {
        .queryFailed(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error")
    }
}
