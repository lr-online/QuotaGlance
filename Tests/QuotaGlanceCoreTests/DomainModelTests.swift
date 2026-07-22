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
        #expect(AppPreferences.default.refreshInterval == .fiveMinutes)
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

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.capturedAt == envelope.capturedAt)
    }
}
