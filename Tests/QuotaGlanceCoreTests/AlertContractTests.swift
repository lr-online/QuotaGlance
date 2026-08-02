import Foundation
import Testing
@testable import QuotaGlanceCore

// Alert contract-fixture decode structs. An input file pins accounts (with
// threshold / episode state) and the fresh snapshots of one batch; an
// expected file pins a subset of AlertBatchEvaluation plus the resulting
// per-account episode state. Only fields present in the file are asserted.
// See Contracts/README.md ("Alert contract fixtures") for the schema.

struct AlertFixtureInput: Decodable {
    struct AccountInput: Decodable {
        let id: UUID
        let displayName: String
        let isEnabled: Bool?
        let lowBalanceThreshold: String?
        let alertEpisodeActive: Bool?

        var account: Account {
            Account(
                id: id,
                displayName: displayName,
                isEnabled: isEnabled ?? true,
                lowBalanceThreshold: lowBalanceThreshold.flatMap { Decimal(string: $0) },
                alertEpisodeActive: alertEpisodeActive ?? false
            )
        }
    }

    struct SnapshotInput: Decodable {
        let accountID: UUID
        let health: HealthInput
        let remaining: ExpectedMoney?

        var snapshot: AccountSnapshot {
            AccountSnapshot(
                accountID: accountID,
                displayName: "",
                usage: remaining.map {
                    ProviderUsageSnapshot(
                        remaining: $0.money,
                        receivedAt: Date(timeIntervalSince1970: 100)
                    )
                },
                health: health.health
            )
        }
    }

    let accounts: [AccountInput]
    let freshSnapshots: [SnapshotInput]
}

struct AlertExpected: Decodable {
    struct NotificationRow: Decodable {
        let accountID: UUID
        let remaining: ExpectedMoney?
    }

    struct AccountRow: Decodable {
        let accountID: UUID
        let alertEpisodeActive: Bool?
    }

    let didChange: Bool?
    let notifications: [NotificationRow]?
    let accounts: [AccountRow]?
}

@Suite("Alert contract fixtures")
struct AlertContractTests {
    @Test("Alert evaluation matches the shared contract fixture", arguments: [
        "notify-on-low",
        "episode-debounce",
        "episode-reset",
        "stale-no-change",
        "batch-notify-and-reset",
        "no-alert-without-threshold",
    ])
    func evaluationMatchesContractFixture(caseName: String) throws {
        let input = try loadBehaviorFixture(
            AlertFixtureInput.self,
            directory: "Alerts",
            file: "\(caseName)-input.json"
        )
        let expected = try loadBehaviorFixture(
            AlertExpected.self,
            directory: "Alerts",
            file: "\(caseName)-expected.json"
        )

        var accounts = input.accounts.map(\.account)
        let freshSnapshots = Dictionary(
            input.freshSnapshots.map { ($0.accountID, $0.snapshot) },
            uniquingKeysWith: { first, _ in first }
        )

        let result = AlertEvaluator.evaluate(
            accounts: &accounts,
            freshSnapshots: freshSnapshots
        )

        if let expectedDidChange = expected.didChange {
            #expect(result.didChange == expectedDidChange)
        }
        if let expectedNotifications = expected.notifications {
            #expect(result.notifications.count == expectedNotifications.count)
            for (actual, expectedRow) in zip(result.notifications, expectedNotifications) {
                #expect(actual.account.id == expectedRow.accountID)
                if let expectedRemaining = expectedRow.remaining {
                    #expect(actual.remaining == expectedRemaining.money)
                }
            }
        }
        if let expectedAccounts = expected.accounts {
            for expectedRow in expectedAccounts {
                let account = accounts.first { $0.id == expectedRow.accountID }
                #expect(account != nil)
                if let expectedActive = expectedRow.alertEpisodeActive {
                    #expect(account?.alertEpisodeActive == expectedActive)
                }
            }
        }
    }
}
