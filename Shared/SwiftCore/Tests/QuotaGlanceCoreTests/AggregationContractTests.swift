import Foundation
import Testing
@testable import QuotaGlanceCore

// Aggregation contract-fixture decode structs. An input file pins accounts,
// snapshots, and the evaluation instant; an expected file pins a subset of
// AggregateSnapshot. Only fields present in the file are asserted; a field
// present with JSON null asserts the value is nil. See Contracts/README.md
// ("Aggregation contract fixtures") for the schema.

struct AggregationFixtureInput: Decodable {
    struct AccountInput: Decodable {
        let id: UUID
        let displayName: String
        let isEnabled: Bool?
        let sortOrder: Int?

        var account: Account {
            Account(
                id: id,
                displayName: displayName,
                isEnabled: isEnabled ?? true,
                sortOrder: sortOrder ?? 0
            )
        }
    }

    struct BalanceInput: Decodable {
        let label: String
        let available: ExpectedMoney
    }

    struct TodayInput: Decodable {
        let actualCost: ExpectedMoney?
        let requests: Int64?
    }

    struct DailyUsageInput: Decodable {
        let date: String
        let actualCost: ExpectedMoney
        let requests: Int64?
        let totalTokens: Int64?
    }

    struct UsageInput: Decodable {
        let balances: [BalanceInput]?
        let today: TodayInput?
        let dailyUsage: [DailyUsageInput]?
    }

    struct SnapshotInput: Decodable {
        let accountID: UUID
        let health: HealthInput
        let usage: UsageInput?

        var snapshot: AccountSnapshot {
            let usage = usage.map { input in
                ProviderUsageSnapshot(
                    balances: (input.balances ?? []).map {
                        MonetaryBalance(label: $0.label, available: $0.available.money)
                    },
                    today: input.today.map {
                        UsageCounters(
                            actualCost: $0.actualCost?.money,
                            requests: $0.requests
                        )
                    },
                    dailyUsage: (input.dailyUsage ?? []).map {
                        DailyUsage(
                            date: $0.date,
                            actualCost: $0.actualCost.money,
                            requests: $0.requests,
                            totalTokens: $0.totalTokens
                        )
                    },
                    receivedAt: Date(timeIntervalSince1970: 100)
                )
            }
            return AccountSnapshot(
                accountID: accountID,
                displayName: "",
                usage: usage,
                health: health.health,
                lastSuccessAt: usage?.receivedAt
            )
        }
    }

    let now: Date
    let accounts: [AccountInput]
    let snapshots: [SnapshotInput]
}

/// Health as fixtures write it: "healthy" / "belowThreshold", or
/// {"stale": "<failure>"} / {"unavailable": "<failure>"} with a
/// SnapshotFailure raw value.
struct HealthInput: Decodable {
    let health: AccountHealth

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            switch name {
            case "healthy":
                health = .healthy
            case "belowThreshold":
                health = .belowThreshold
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown health '\(name)'."
                )
            }
            return
        }
        let table = try container.decode([String: String].self)
        guard let (kind, failureName) = table.first,
              let failure = SnapshotFailure(rawValue: failureName) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown health object."
            )
        }
        switch kind {
        case "stale":
            health = .stale(failure)
        case "unavailable":
            health = .unavailable(failure)
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown health kind '\(kind)'."
            )
        }
    }
}

struct AggregationExpected: Decodable {
    struct AccountRow: Decodable {
        let accountID: UUID
        let displayName: String?
    }

    struct DailyUsageRow: Decodable {
        let date: String
        let actualCost: ExpectedMoney?
    }

    /// Tri-state field: absent = unchecked, null = assert nil, value = assert
    /// equal. Fixtures use this for metrics that must stay absent.
    enum OptionalField<Value: Decodable> {
        case unchecked
        case assertNil
        case assertValue(Value)

        init(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws {
            guard container.contains(key) else {
                self = .unchecked
                return
            }
            if let value = try container.decodeIfPresent(Value.self, forKey: key) {
                self = .assertValue(value)
            } else {
                self = .assertNil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case balances
        case todayActualCost
        case todayRequests
        case dailyUsage
        case accounts
        case isPartial
    }

    let balances: [ExpectedMoney]?
    let todayActualCost: OptionalField<ExpectedMoney>
    let todayRequests: OptionalField<Int64>
    let dailyUsage: [DailyUsageRow]?
    let accounts: [AccountRow]?
    let isPartial: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balances = try container.decodeIfPresent([ExpectedMoney].self, forKey: .balances)
        todayActualCost = try OptionalField(container: container, key: .todayActualCost)
        todayRequests = try OptionalField(container: container, key: .todayRequests)
        dailyUsage = try container.decodeIfPresent([DailyUsageRow].self, forKey: .dailyUsage)
        accounts = try container.decodeIfPresent([AccountRow].self, forKey: .accounts)
        isPartial = try container.decodeIfPresent(Bool.self, forKey: .isPartial)
    }
}

func behaviorContractsDirectory(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // QuotaGlanceCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Shared/SwiftCore
        .deletingLastPathComponent() // Shared
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("Contracts/\(name)", isDirectory: true)
}

func loadBehaviorFixture<T: Decodable>(_ type: T.Type, directory: String, file: String) throws -> T {
    let url = behaviorContractsDirectory(directory).appendingPathComponent(file)
    return try JSONDecoder.quotaGlance.decode(T.self, from: Data(contentsOf: url))
}

@Suite("Aggregation contract fixtures")
struct AggregationContractTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test("Aggregate matches the shared contract fixture", arguments: [
        "healthy-sum",
        "stale-partial",
        "disabled-excluded",
        "mixed-currency",
        "missing-metrics",
        "request-overflow",
    ])
    func aggregateMatchesContractFixture(caseName: String) throws {
        let input = try loadBehaviorFixture(
            AggregationFixtureInput.self,
            directory: "Aggregation",
            file: "\(caseName)-input.json"
        )
        let expected = try loadBehaviorFixture(
            AggregationExpected.self,
            directory: "Aggregation",
            file: "\(caseName)-expected.json"
        )

        let aggregate = SnapshotAggregator(calendar: Self.calendar).aggregate(
            accounts: input.accounts.map(\.account),
            snapshots: input.snapshots.map(\.snapshot),
            now: input.now
        )

        if let expectedBalances = expected.balances {
            #expect(aggregate.balances == expectedBalances.map(\.money))
        }
        switch expected.todayActualCost {
        case .unchecked:
            break
        case .assertNil:
            #expect(aggregate.todayActualCost == nil)
        case let .assertValue(money):
            #expect(aggregate.todayActualCost == money.money)
        }
        switch expected.todayRequests {
        case .unchecked:
            break
        case .assertNil:
            #expect(aggregate.todayRequests == nil)
        case let .assertValue(requests):
            #expect(aggregate.todayRequests == requests)
        }
        if let expectedDaily = expected.dailyUsage {
            #expect(aggregate.dailyUsage.count == expectedDaily.count)
            for (actualEntry, expectedEntry) in zip(aggregate.dailyUsage, expectedDaily) {
                #expect(actualEntry.date == expectedEntry.date)
                if let expectedCost = expectedEntry.actualCost {
                    #expect(actualEntry.actualCost == expectedCost.money)
                }
            }
        }
        if let expectedAccounts = expected.accounts {
            #expect(aggregate.accounts.count == expectedAccounts.count)
            for (actualAccount, expectedRow) in zip(aggregate.accounts, expectedAccounts) {
                #expect(actualAccount.accountID == expectedRow.accountID)
                if let expectedName = expectedRow.displayName {
                    #expect(actualAccount.displayName == expectedName)
                }
            }
        }
        if let expectedPartial = expected.isPartial {
            #expect(aggregate.isPartial == expectedPartial)
        }
    }
}
