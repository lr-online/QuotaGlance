import Foundation
import SQLite3
import Testing
@testable import QuotaGlanceCore

@Suite("cc-switch usage reader")
struct CCSwitchUsageReaderTests {
    @Test("Aggregates the cc-switch log and applies the selected app filter")
    func aggregatesAndFilters() throws {
        let fixture = try CCSwitchDatabaseFixture()
        try fixture.insert(
            createdAt: 9_950,
            app: "codex",
            providerID: "openai",
            model: "gpt-5",
            input: 100,
            output: 40,
            cacheRead: 20,
            cacheCreation: 5,
            cost: 0.0125,
            latency: 400,
            firstToken: 120,
            status: 200
        )
        try fixture.insert(
            createdAt: 9_970,
            app: "claude",
            providerID: "anthropic",
            model: "claude-opus",
            input: 50,
            output: 10,
            cacheRead: 0,
            cacheCreation: 0,
            cost: 0.02,
            latency: 800,
            firstToken: 300,
            status: 429,
            error: "rate limited"
        )
        try fixture.insert(
            createdAt: 8_000,
            app: "codex",
            providerID: "openai",
            model: "older",
            input: 900,
            output: 900,
            cacheRead: 0,
            cacheCreation: 0,
            cost: 2,
            latency: 100,
            firstToken: 40,
            status: 200
        )

        let reader = CCSwitchUsageReader(databaseURL: fixture.url)
        let dashboard = try reader.load(
            range: CCSwitchTimeRange(seconds: 100, label: "100s"),
            now: Date(timeIntervalSince1970: 10_000)
        )

        #expect(dashboard.summary.requests == 2)
        #expect(dashboard.summary.successfulRequests == 1)
        #expect(dashboard.summary.failedRequests == 1)
        #expect(dashboard.summary.inputTokens == 150)
        #expect(dashboard.summary.outputTokens == 50)
        #expect(dashboard.summary.cacheReadTokens == 20)
        #expect(dashboard.summary.cacheCreationTokens == 5)
        #expect(dashboard.summary.costUSD == Decimal(string: "0.0325"))
        #expect(dashboard.summary.medianLatencyMilliseconds == 600)
        #expect(dashboard.summary.averageFirstTokenMilliseconds == 210)
        #expect(dashboard.applications.map(\.name) == ["codex", "claude"])
        #expect(dashboard.providers.first?.name == "OpenAI")
        #expect(dashboard.models.map(\.name) == ["gpt-5", "claude-opus"])
        #expect(dashboard.failures == [
            CCSwitchFailure(statusCode: 429, count: 1, sampleMessage: "rate limited"),
        ])
        #expect(dashboard.recentRequests.first?.app == "claude")

        let codex = try reader.load(
            range: CCSwitchTimeRange(seconds: 100, label: "100s"),
            app: "codex",
            now: Date(timeIntervalSince1970: 10_000)
        )
        #expect(codex.summary.requests == 1)
        #expect(codex.summary.totalTokens == 165)
        #expect(codex.applications.map(\.name) == ["codex"])
        #expect(codex.failures.isEmpty)
    }

    @Test("Locates macOS and Linux conventional databases in a predictable order")
    func locatesConventionalDatabases() {
        let home = URL(fileURLWithPath: "/tmp/cc-switch-home", isDirectory: true)
        let candidates = CCSwitchDatabaseLocator.candidateURLs(
            environment: ["CC_SWITCH_DB": "/tmp/override.sqlite"],
            homeDirectory: home
        )
        #expect(candidates.map(\.path) == [
            "/tmp/override.sqlite",
            "/tmp/cc-switch-home/.cc-switch/cc-switch.db",
            "/tmp/cc-switch-home/Library/Application Support/cc-switch/proxy_request_logs.sqlite",
            "/tmp/cc-switch-home/.local/share/cc-switch/proxy_request_logs.sqlite",
            "/tmp/cc-switch-home/.config/cc-switch/proxy_request_logs.sqlite",
        ])
    }

    @Test("Orders breakdown rows by request tokens, not cache tokens")
    func breakdownOrderingUsesRequestTokens() throws {
        let fixture = try CCSwitchDatabaseFixture()
        try fixture.insert(
            createdAt: 9_950,
            app: "high-output",
            providerID: "openai",
            model: "gpt-5",
            input: 900,
            output: 100,
            cacheRead: 0,
            cacheCreation: 0,
            cost: 0,
            latency: 100,
            firstToken: 40,
            status: 200
        )
        try fixture.insert(
            createdAt: 9_960,
            app: "cache-heavy",
            providerID: "openai",
            model: "gpt-5",
            input: 1,
            output: 1,
            cacheRead: 50_000,
            cacheCreation: 0,
            cost: 0,
            latency: 100,
            firstToken: 40,
            status: 200
        )

        let dashboard = try CCSwitchUsageReader(databaseURL: fixture.url).load(
            range: CCSwitchTimeRange(seconds: 100, label: "100s"),
            now: Date(timeIntervalSince1970: 10_000)
        )

        #expect(dashboard.applications.map(\.name) == ["high-output", "cache-heavy"])
    }
}

private final class CCSwitchDatabaseFixture {
    let directory: URL
    let url: URL
    private var db: OpaquePointer?

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("cc-switch.db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw FixtureError.open }
        try execute("""
        CREATE TABLE proxy_request_logs (
          created_at REAL, app_type TEXT, provider_id TEXT, model TEXT,
          input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
          cache_creation_tokens INTEGER, total_cost_usd TEXT, latency_ms REAL,
          first_token_ms REAL, status_code INTEGER, error_message TEXT
        );
        CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT);
        INSERT INTO providers VALUES ('openai', 'codex', 'OpenAI');
        INSERT INTO providers VALUES ('anthropic', 'claude', 'Anthropic');
        """)
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: directory)
    }

    func insert(
        createdAt: Double,
        app: String,
        providerID: String,
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheCreation: Int,
        cost: Double,
        latency: Double,
        firstToken: Double,
        status: Int,
        error: String? = nil
    ) throws {
        let sql = """
        INSERT INTO proxy_request_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw FixtureError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, createdAt)
        bind(app, to: statement, at: 2)
        bind(providerID, to: statement, at: 3)
        bind(model, to: statement, at: 4)
        sqlite3_bind_int64(statement, 5, Int64(input))
        sqlite3_bind_int64(statement, 6, Int64(output))
        sqlite3_bind_int64(statement, 7, Int64(cacheRead))
        sqlite3_bind_int64(statement, 8, Int64(cacheCreation))
        sqlite3_bind_double(statement, 9, cost)
        sqlite3_bind_double(statement, 10, latency)
        sqlite3_bind_double(statement, 11, firstToken)
        sqlite3_bind_int(statement, 12, Int32(status))
        if let error { bind(error, to: statement, at: 13) } else { sqlite3_bind_null(statement, 13) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.query }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.query }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private enum FixtureError: Error { case open, query }
}
