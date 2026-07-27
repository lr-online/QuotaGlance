import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Domain models")
struct DomainModelTests {
    @Test("Money round-trips without Double conversion")
    func moneyRoundTripsWithoutDoubleConversion() throws {
        let money = Money(
            amount: Decimal(string: "544.045471")!,
            currency: "USD"
        )

        let data = try JSONEncoder.quotaGlance.encode(money)
        let decoded = try JSONDecoder.quotaGlance.decode(Money.self, from: data)

        #expect(decoded == money)
    }

    @Test("New accounts and app preferences use safe defaults")
    func newAccountDefaultsToEnabledAndFiveMinuteRefresh() {
        let account = Account(displayName: "Primary")

        #expect(account.isEnabled)
        #expect(account.lowBalanceThreshold == nil)
        #expect(account.provider == .apiInfo)
        #expect(account.detectedProfile == .apiInfo)
        #expect(AppPreferences.default.refreshInterval == .fiveMinutes)
    }

    @Test("Provider profiles round-trip all supported variants")
    func providerProfilesRoundTrip() throws {
        let profiles = [
            ProviderProfile(region: .global, credentialKind: .standard),
            ProviderProfile(region: .china, credentialKind: .standard),
            ProviderProfile(region: .international, credentialKind: .management),
            ProviderProfile(region: .international, credentialKind: .tokenPlan),
        ]

        for profile in profiles {
            let data = try JSONEncoder.quotaGlance.encode(profile)
            let decoded = try JSONDecoder.quotaGlance.decode(
                ProviderProfile.self,
                from: data
            )
            #expect(decoded == profile)
        }
        #expect(ProviderID.allCases == [
            .apiInfo,
            .deepSeek,
            .kimi,
            .openRouter,
            .miniMax,
        ])
    }

    @Test("Provider profiles produce concise account labels")
    func providerProfilesProduceAccountLabels() {
        #expect(
            ProviderID.kimi.profileDescription(
                for: ProviderProfile(region: .china, credentialKind: .standard)
            ) == "China / CNY"
        )
        #expect(
            ProviderID.kimi.profileDescription(
                for: ProviderProfile(region: .international, credentialKind: .standard)
            ) == "International / USD"
        )
        #expect(
            ProviderID.openRouter.profileDescription(
                for: ProviderProfile(region: .global, credentialKind: .management)
            ) == "Management key"
        )
        #expect(
            ProviderID.miniMax.profileDescription(
                for: ProviderProfile(region: .international, credentialKind: .tokenPlan)
            ) == "International / Token Plan"
        )
        #expect(ProviderID.deepSeek.profileDescription(for: nil) == "Not detected")
    }

    @Test("Low-balance thresholds are available only for balance credentials")
    func lowBalanceThresholdAvailabilityTracksCredentialCapabilities() {
        let standard = ProviderProfile(region: .global, credentialKind: .standard)
        let management = ProviderProfile(region: .global, credentialKind: .management)
        let tokenPlan = ProviderProfile(region: .china, credentialKind: .tokenPlan)

        #expect(ProviderID.apiInfo.supportsLowBalanceThreshold(profile: standard))
        #expect(ProviderID.deepSeek.supportsLowBalanceThreshold(profile: standard))
        #expect(ProviderID.kimi.supportsLowBalanceThreshold(profile: standard))
        #expect(ProviderID.openRouter.supportsLowBalanceThreshold(profile: nil))
        #expect(!ProviderID.openRouter.supportsLowBalanceThreshold(profile: standard))
        #expect(ProviderID.openRouter.supportsLowBalanceThreshold(profile: management))
        #expect(!ProviderID.miniMax.supportsLowBalanceThreshold(profile: tokenPlan))
        #expect(
            ProviderID.miniMax.normalizedLowBalanceThreshold(
                20,
                profile: tokenPlan
            ) == nil
        )
    }

    @Test("Legacy accounts migrate to API Info")
    func legacyAccountMigratesToAPIInfo() throws {
        let data = Data(
            #"{"alertEpisodeActive":false,"displayName":"Legacy","id":"00000000-0000-0000-0000-000000000001","isEnabled":true,"sortOrder":0}"#.utf8
        )

        let account = try JSONDecoder.quotaGlance.decode(Account.self, from: data)

        #expect(account.provider == .apiInfo)
        #expect(account.detectedProfile == .apiInfo)
    }

    @Test("Provider snapshots allow quota windows without money")
    func providerSnapshotsAllowQuotaWindowsWithoutMoney() throws {
        let snapshot = ProviderUsageSnapshot(
            quotaWindows: [
                QuotaWindow(
                    label: "5-hour quota",
                    used: 100,
                    limit: 1_000,
                    remaining: 900,
                    unit: "requests"
                )
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )

        let data = try JSONEncoder.quotaGlance.encode(snapshot)
        let decoded = try JSONDecoder.quotaGlance.decode(
            ProviderUsageSnapshot.self,
            from: data
        )

        #expect(decoded.balances.isEmpty)
        #expect(decoded.spendingLimit == nil)
        #expect(decoded.quotaWindows.first?.remaining == 900)
        #expect(decoded.primaryBalance == nil)
    }

    @Test("Monetary capabilities preserve semantic boundaries")
    func monetaryCapabilitiesPreserveSemanticBoundaries() {
        let balance = MonetaryBalance(
            label: "Balance",
            available: Money(amount: 50, currency: "cny"),
            breakdown: [
                MonetaryValue(
                    label: "Cash",
                    value: Money(amount: 30, currency: "CNY")
                )
            ]
        )
        let limit = SpendingLimit(
            label: "Key limit",
            used: Money(amount: 25, currency: "USD"),
            limit: Money(amount: 100, currency: "USD"),
            remaining: Money(amount: 75, currency: "USD")
        )
        let snapshot = ProviderUsageSnapshot(
            balances: [balance],
            spendingLimit: limit,
            receivedAt: .now
        )

        #expect(snapshot.primaryBalance?.available.currency == "CNY")
        #expect(snapshot.spendingLimit?.remaining?.currency == "USD")
    }

    @Test("Widget snapshot envelope preserves schema version")
    func snapshotEnvelopeRoundTripsSchemaVersion() throws {
        let envelope = WidgetSnapshotEnvelope.empty(
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        let data = try JSONEncoder.quotaGlance.encode(envelope)
        let decoded = try JSONDecoder.quotaGlance.decode(
            WidgetSnapshotEnvelope.self,
            from: data
        )

        #expect(decoded.schemaVersion == 2)
        #expect(decoded.capturedAt == envelope.capturedAt)
    }
}
