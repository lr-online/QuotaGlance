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
            .bioMapCoding,
        ])
    }

    @Test("Provider profiles produce concise account labels")
    func providerProfilesProduceAccountLabels() {
        #expect(
            ProviderCatalog.descriptor(for: .kimi).profileDescription(
                ProviderProfile(region: .china, credentialKind: .standard),
                .english
            ) == "China / CNY"
        )
        #expect(
            ProviderCatalog.descriptor(for: .kimi).profileDescription(
                ProviderProfile(region: .international, credentialKind: .standard),
                .english
            ) == "International / USD"
        )
        #expect(
            ProviderCatalog.descriptor(for: .openRouter).profileDescription(
                ProviderProfile(region: .global, credentialKind: .management),
                .english
            ) == "Management key"
        )
        #expect(
            ProviderCatalog.descriptor(for: .miniMax).profileDescription(
                ProviderProfile(region: .international, credentialKind: .tokenPlan),
                .english
            ) == "International / Token Plan"
        )
        #expect(
            ProviderCatalog.descriptor(for: .deepSeek)
                .profileDescription(nil, .english) == "Not detected"
        )
        #expect(
            ProviderCatalog.descriptor(for: .bioMapCoding).displayName
                == "BioMap Coding"
        )
        #expect(
            ProviderCatalog.descriptor(for: .bioMapCoding).profileDescription(
                ProviderProfile(region: .global, credentialKind: .standard),
                .english
            ) == "Global / Standard key"
        )
    }

    @Test("Low-balance thresholds are available only for balance credentials")
    func lowBalanceThresholdAvailabilityTracksCredentialCapabilities() {
        let standard = ProviderProfile(region: .global, credentialKind: .standard)
        let management = ProviderProfile(region: .global, credentialKind: .management)
        let tokenPlan = ProviderProfile(region: .china, credentialKind: .tokenPlan)

        #expect(
            ProviderCatalog.descriptor(for: .apiInfo)
                .supportsLowBalanceThreshold(standard)
        )
        #expect(
            ProviderCatalog.descriptor(for: .deepSeek)
                .supportsLowBalanceThreshold(standard)
        )
        #expect(
            ProviderCatalog.descriptor(for: .kimi)
                .supportsLowBalanceThreshold(standard)
        )
        #expect(
            ProviderCatalog.descriptor(for: .openRouter)
                .supportsLowBalanceThreshold(nil)
        )
        #expect(
            !ProviderCatalog.descriptor(for: .openRouter)
                .supportsLowBalanceThreshold(standard)
        )
        #expect(
            ProviderCatalog.descriptor(for: .openRouter)
                .supportsLowBalanceThreshold(management)
        )
        #expect(
            !ProviderCatalog.descriptor(for: .miniMax)
                .supportsLowBalanceThreshold(tokenPlan)
        )
        #expect(
            !ProviderCatalog.descriptor(for: .bioMapCoding)
                .supportsLowBalanceThreshold(standard)
        )
        #expect(
            ProviderCatalog.descriptor(for: .miniMax)
                .normalizedLowBalanceThreshold(
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

    @Test("Notification Center widget default account starts unset")
    func notificationCenterDefaultAccountStartsUnset() {
        #expect(AppPreferences.default.notificationCenterDefaultAccountID == nil)
        #expect(AppPreferences.default.preferredLanguage == .system)
        #expect(AppPreferences.default.preferredTheme == .system)
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
