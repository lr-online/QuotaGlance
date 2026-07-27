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

public struct MonetaryValue: Codable, Equatable, Identifiable, Sendable {
    public var id: String { label }
    public var label: String
    public var value: Money

    public init(label: String, value: Money) {
        self.label = label
        self.value = value
    }
}

public struct MonetaryBalance: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(label)-\(available.currency)" }
    public var label: String
    public var available: Money
    public var breakdown: [MonetaryValue]

    public init(
        label: String,
        available: Money,
        breakdown: [MonetaryValue] = []
    ) {
        self.label = label
        self.available = available
        self.breakdown = breakdown
    }
}

public struct SpendingLimit: Codable, Equatable, Sendable {
    public var label: String
    public var used: Money?
    public var limit: Money?
    public var remaining: Money?
    public var resetDescription: String?

    public init(
        label: String,
        used: Money? = nil,
        limit: Money? = nil,
        remaining: Money? = nil,
        resetDescription: String? = nil
    ) {
        self.label = label
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.resetDescription = resetDescription
    }
}

public struct SpendSummary: Codable, Equatable, Sendable {
    public var today: Money?
    public var week: Money?
    public var month: Money?
    public var total: Money?

    public init(
        today: Money? = nil,
        week: Money? = nil,
        month: Money? = nil,
        total: Money? = nil
    ) {
        self.today = today
        self.week = week
        self.month = month
        self.total = total
    }

    public var isEmpty: Bool {
        today == nil && week == nil && month == nil && total == nil
    }
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String { label }
    public var label: String
    public var used: Decimal?
    public var limit: Decimal?
    public var remaining: Decimal?
    public var unit: String
    public var resetsAt: Date?

    public init(
        label: String,
        used: Decimal? = nil,
        limit: Decimal? = nil,
        remaining: Decimal? = nil,
        unit: String,
        resetsAt: Date? = nil
    ) {
        self.label = label
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.unit = unit
        self.resetsAt = resetsAt
    }
}

public struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    public var balances: [MonetaryBalance]
    public var spendingLimit: SpendingLimit?
    public var spend: SpendSummary
    public var quotaWindows: [QuotaWindow]
    public var today: UsageCounters?
    public var total: UsageCounters?
    public var dailyUsage: [DailyUsage]
    public var modelUsage: [ModelUsage]
    public var providerStatus: String?
    public var metricsUnavailableReason: String?
    public var receivedAt: Date

    public init(
        balances: [MonetaryBalance] = [],
        spendingLimit: SpendingLimit? = nil,
        spend: SpendSummary = SpendSummary(),
        quotaWindows: [QuotaWindow] = [],
        today: UsageCounters? = nil,
        total: UsageCounters? = nil,
        dailyUsage: [DailyUsage] = [],
        modelUsage: [ModelUsage] = [],
        providerStatus: String? = nil,
        metricsUnavailableReason: String? = nil,
        receivedAt: Date
    ) {
        self.balances = balances
        self.spendingLimit = spendingLimit
        self.spend = spend
        self.quotaWindows = quotaWindows
        self.today = today
        self.total = total
        self.dailyUsage = dailyUsage
        self.modelUsage = modelUsage
        self.providerStatus = providerStatus
        self.metricsUnavailableReason = metricsUnavailableReason
        self.receivedAt = receivedAt
    }

    public init(
        remaining: Money,
        quotaLimit: Money? = nil,
        quotaUsed: Money? = nil,
        today: UsageCounters? = nil,
        total: UsageCounters? = nil,
        dailyUsage: [DailyUsage] = [],
        modelUsage: [ModelUsage] = [],
        providerStatus: String? = nil,
        metricsUnavailableReason: String? = nil,
        receivedAt: Date
    ) {
        self.init(
            balances: [MonetaryBalance(label: "Balance", available: remaining)],
            spendingLimit: quotaLimit != nil || quotaUsed != nil
                ? SpendingLimit(
                    label: "Quota",
                    used: quotaUsed,
                    limit: quotaLimit,
                    remaining: nil
                )
                : nil,
            spend: SpendSummary(
                today: today?.actualCost,
                total: total?.actualCost
            ),
            today: today,
            total: total,
            dailyUsage: dailyUsage,
            modelUsage: modelUsage,
            providerStatus: providerStatus,
            metricsUnavailableReason: metricsUnavailableReason,
            receivedAt: receivedAt
        )
    }

    public var primaryBalance: MonetaryBalance? {
        balances.first
    }

    public var remaining: Money? {
        primaryBalance?.available
    }

    public var quotaLimit: Money? {
        spendingLimit?.limit
    }

    public var quotaUsed: Money? {
        spendingLimit?.used
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
    public var provider: ProviderID
    public var detectedProfile: ProviderProfile?
    public var lowBalanceThreshold: Decimal?
    public var usage: ProviderUsageSnapshot?
    public var health: AccountHealth
    public var lastSuccessAt: Date?

    public init(
        accountID: UUID,
        displayName: String,
        provider: ProviderID = .apiInfo,
        detectedProfile: ProviderProfile? = nil,
        lowBalanceThreshold: Decimal? = nil,
        usage: ProviderUsageSnapshot? = nil,
        health: AccountHealth,
        lastSuccessAt: Date? = nil
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.provider = provider
        self.detectedProfile = detectedProfile ?? (provider == .apiInfo ? .apiInfo : nil)
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
    public var balances: [Money]
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accounts: [AccountSnapshot]
    public var isPartial: Bool

    public init(
        remaining: Money? = nil,
        balances: [Money]? = nil,
        todayActualCost: Money? = nil,
        todayRequests: Int64? = nil,
        dailyUsage: [DailyUsage] = [],
        accounts: [AccountSnapshot] = [],
        isPartial: Bool = false
    ) {
        self.balances = balances ?? remaining.map { [$0] } ?? []
        self.todayActualCost = todayActualCost
        self.todayRequests = todayRequests
        self.dailyUsage = dailyUsage
        self.accounts = accounts
        self.isPartial = isPartial
    }

    public var remaining: Money? {
        balances.count == 1 ? balances[0] : nil
    }
}

public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

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
