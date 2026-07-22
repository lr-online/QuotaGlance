import Foundation

public struct UsageCounters: Codable, Equatable, Sendable {
    public var actualCost: Money?
    public var requests: Int64?
    public var inputTokens: Int64?
    public var outputTokens: Int64?
    public var cacheReadTokens: Int64?
    public var cacheCreationTokens: Int64?
    public var totalTokens: Int64?

    public init(
        actualCost: Money? = nil,
        requests: Int64? = nil,
        inputTokens: Int64? = nil,
        outputTokens: Int64? = nil,
        cacheReadTokens: Int64? = nil,
        cacheCreationTokens: Int64? = nil,
        totalTokens: Int64? = nil
    ) {
        self.actualCost = actualCost
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.totalTokens = totalTokens
    }
}

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { date }
    public var date: String
    public var actualCost: Money
    public var requests: Int64?
    public var totalTokens: Int64?

    public init(
        date: String,
        actualCost: Money,
        requests: Int64? = nil,
        totalTokens: Int64? = nil
    ) {
        self.date = date
        self.actualCost = actualCost
        self.requests = requests
        self.totalTokens = totalTokens
    }
}

public struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }
    public var model: String
    public var actualCost: Money?
    public var requests: Int64?
    public var totalTokens: Int64?

    public init(
        model: String,
        actualCost: Money? = nil,
        requests: Int64? = nil,
        totalTokens: Int64? = nil
    ) {
        self.model = model
        self.actualCost = actualCost
        self.requests = requests
        self.totalTokens = totalTokens
    }
}

public struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    public var remaining: Money
    public var quotaLimit: Money?
    public var quotaUsed: Money?
    public var today: UsageCounters?
    public var total: UsageCounters?
    public var dailyUsage: [DailyUsage]
    public var modelUsage: [ModelUsage]
    public var providerStatus: String?
    public var receivedAt: Date

    public init(
        remaining: Money,
        quotaLimit: Money? = nil,
        quotaUsed: Money? = nil,
        today: UsageCounters? = nil,
        total: UsageCounters? = nil,
        dailyUsage: [DailyUsage] = [],
        modelUsage: [ModelUsage] = [],
        providerStatus: String? = nil,
        receivedAt: Date
    ) {
        self.remaining = remaining
        self.quotaLimit = quotaLimit
        self.quotaUsed = quotaUsed
        self.today = today
        self.total = total
        self.dailyUsage = dailyUsage
        self.modelUsage = modelUsage
        self.providerStatus = providerStatus
        self.receivedAt = receivedAt
    }
}

public enum SnapshotFailure: String, Codable, Equatable, Sendable {
    case missingCredential
    case invalidCredential
    case rateLimited
    case offline
    case timeout
    case invalidResponse
    case providerError
}

public enum AccountHealth: Codable, Equatable, Sendable {
    case healthy
    case belowThreshold
    case stale(SnapshotFailure)
    case unavailable(SnapshotFailure)
}

public struct AccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { accountID }
    public var accountID: UUID
    public var displayName: String
    public var lowBalanceThreshold: Decimal?
    public var usage: ProviderUsageSnapshot?
    public var health: AccountHealth
    public var lastSuccessAt: Date?

    public init(
        accountID: UUID,
        displayName: String,
        lowBalanceThreshold: Decimal? = nil,
        usage: ProviderUsageSnapshot? = nil,
        health: AccountHealth,
        lastSuccessAt: Date? = nil
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.lowBalanceThreshold = lowBalanceThreshold
        self.usage = usage
        self.health = health
        self.lastSuccessAt = lastSuccessAt
    }

    public var remaining: Money? {
        usage?.remaining
    }
}

public struct AggregateSnapshot: Codable, Equatable, Sendable {
    public var remaining: Money?
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accounts: [AccountSnapshot]
    public var isPartial: Bool

    public init(
        remaining: Money? = nil,
        todayActualCost: Money? = nil,
        todayRequests: Int64? = nil,
        dailyUsage: [DailyUsage] = [],
        accounts: [AccountSnapshot] = [],
        isPartial: Bool = false
    ) {
        self.remaining = remaining
        self.todayActualCost = todayActualCost
        self.todayRequests = todayRequests
        self.dailyUsage = dailyUsage
        self.accounts = accounts
        self.isPartial = isPartial
    }
}

public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var capturedAt: Date
    public var aggregate: AggregateSnapshot
    public var accounts: [AccountSnapshot]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        capturedAt: Date,
        aggregate: AggregateSnapshot,
        accounts: [AccountSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.aggregate = aggregate
        self.accounts = accounts
    }

    public static func empty(capturedAt: Date) -> Self {
        Self(
            capturedAt: capturedAt,
            aggregate: AggregateSnapshot(),
            accounts: []
        )
    }
}

public extension JSONEncoder {
    static var quotaGlance: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var quotaGlance: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
