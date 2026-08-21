import Foundation

/// A local, read-only view of cc-switch proxy request logs.
///
/// The source database belongs to cc-switch. QuotaGlance never creates,
/// migrates, writes, or otherwise mutates it.
public struct CCSwitchTimeRange: Equatable, Hashable, Sendable, Identifiable {
    public let seconds: TimeInterval
    public let label: String

    public var id: TimeInterval { seconds }

    public init(seconds: TimeInterval, label: String) {
        self.seconds = seconds
        self.label = label
    }

    public static let fiveMinutes = Self(seconds: 5 * 60, label: "5m")
    public static let fifteenMinutes = Self(seconds: 15 * 60, label: "15m")
    public static let oneHour = Self(seconds: 60 * 60, label: "1h")
    public static let sixHours = Self(seconds: 6 * 60 * 60, label: "6h")
    public static let oneDay = Self(seconds: 24 * 60 * 60, label: "24h")

    public static let standardRanges = [
        fiveMinutes, fifteenMinutes, oneHour, sixHours, oneDay,
    ]
}

public struct CCSwitchUsageSummary: Equatable, Sendable {
    public let requests: Int
    public let successfulRequests: Int
    public let failedRequests: Int
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let cacheCreationTokens: Int64
    public let costUSD: Decimal
    public let medianLatencyMilliseconds: Double?
    public let averageFirstTokenMilliseconds: Double?

    public init(
        requests: Int,
        successfulRequests: Int,
        failedRequests: Int,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheCreationTokens: Int64,
        costUSD: Decimal,
        medianLatencyMilliseconds: Double?,
        averageFirstTokenMilliseconds: Double?
    ) {
        self.requests = requests
        self.successfulRequests = successfulRequests
        self.failedRequests = failedRequests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.costUSD = costUSD
        self.medianLatencyMilliseconds = medianLatencyMilliseconds
        self.averageFirstTokenMilliseconds = averageFirstTokenMilliseconds
    }

    public var totalTokens: Int64 {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public var failureRate: Double {
        guard requests > 0 else { return 0 }
        return Double(failedRequests) / Double(requests)
    }
}

public struct CCSwitchTimelinePoint: Equatable, Identifiable, Sendable {
    public let startedAt: Date
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let requestCount: Int

    public var id: Date { startedAt }
    public var totalTokens: Int64 { inputTokens + outputTokens + cacheReadTokens }

    public init(
        startedAt: Date,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        requestCount: Int
    ) {
        self.startedAt = startedAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.requestCount = requestCount
    }
}

public struct CCSwitchBreakdownRow: Equatable, Identifiable, Sendable {
    public let name: String
    public let detail: String?
    public let requests: Int
    public let failures: Int
    public let tokens: Int64
    public let cacheReadTokens: Int64
    public let costUSD: Decimal
    public let averageLatencyMilliseconds: Double?

    public var id: String { detail.map { "\(name)|\($0)" } ?? name }

    public init(
        name: String,
        detail: String? = nil,
        requests: Int,
        failures: Int,
        tokens: Int64,
        cacheReadTokens: Int64,
        costUSD: Decimal,
        averageLatencyMilliseconds: Double?
    ) {
        self.name = name
        self.detail = detail
        self.requests = requests
        self.failures = failures
        self.tokens = tokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.averageLatencyMilliseconds = averageLatencyMilliseconds
    }
}

public struct CCSwitchFailure: Equatable, Identifiable, Sendable {
    public let statusCode: Int
    public let count: Int
    public let sampleMessage: String?

    public var id: Int { statusCode }

    public init(statusCode: Int, count: Int, sampleMessage: String?) {
        self.statusCode = statusCode
        self.count = count
        self.sampleMessage = sampleMessage
    }
}

public struct CCSwitchRecentRequest: Equatable, Identifiable, Sendable {
    public let createdAt: Date
    public let app: String
    public let provider: String
    public let model: String
    public let outputTokens: Int64
    public let latencyMilliseconds: Double?
    public let statusCode: Int

    public var id: String {
        "\(createdAt.timeIntervalSince1970)|\(app)|\(provider)|\(model)|\(statusCode)"
    }

    public init(
        createdAt: Date,
        app: String,
        provider: String,
        model: String,
        outputTokens: Int64,
        latencyMilliseconds: Double?,
        statusCode: Int
    ) {
        self.createdAt = createdAt
        self.app = app
        self.provider = provider
        self.model = model
        self.outputTokens = outputTokens
        self.latencyMilliseconds = latencyMilliseconds
        self.statusCode = statusCode
    }
}

public struct CCSwitchUsageDashboard: Equatable, Sendable {
    public let databaseURL: URL
    public let range: CCSwitchTimeRange
    public let selectedApp: String?
    public let capturedAt: Date
    public let summary: CCSwitchUsageSummary
    public let timeline: [CCSwitchTimelinePoint]
    public let applications: [CCSwitchBreakdownRow]
    public let providers: [CCSwitchBreakdownRow]
    public let models: [CCSwitchBreakdownRow]
    public let failures: [CCSwitchFailure]
    public let recentRequests: [CCSwitchRecentRequest]

    public init(
        databaseURL: URL,
        range: CCSwitchTimeRange,
        selectedApp: String?,
        capturedAt: Date,
        summary: CCSwitchUsageSummary,
        timeline: [CCSwitchTimelinePoint],
        applications: [CCSwitchBreakdownRow],
        providers: [CCSwitchBreakdownRow],
        models: [CCSwitchBreakdownRow],
        failures: [CCSwitchFailure],
        recentRequests: [CCSwitchRecentRequest]
    ) {
        self.databaseURL = databaseURL
        self.range = range
        self.selectedApp = selectedApp
        self.capturedAt = capturedAt
        self.summary = summary
        self.timeline = timeline
        self.applications = applications
        self.providers = providers
        self.models = models
        self.failures = failures
        self.recentRequests = recentRequests
    }

    public var knownApps: [String] {
        applications.map(\.name)
    }
}

public enum CCSwitchDatabaseLocator {
    public static func candidateURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var candidates: [URL] = []
        if let override = environment["CC_SWITCH_DB"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(homeDirectory.appendingPathComponent(".cc-switch/cc-switch.db"))
        candidates.append(
            homeDirectory.appendingPathComponent(
                "Library/Application Support/cc-switch/proxy_request_logs.sqlite"
            )
        )
        candidates.append(
            homeDirectory.appendingPathComponent(
                ".local/share/cc-switch/proxy_request_logs.sqlite"
            )
        )
        candidates.append(
            homeDirectory.appendingPathComponent(
                ".config/cc-switch/proxy_request_logs.sqlite"
            )
        )
        return candidates
    }

    public static func firstExistingURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        candidateURLs(environment: environment, homeDirectory: homeDirectory).first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
