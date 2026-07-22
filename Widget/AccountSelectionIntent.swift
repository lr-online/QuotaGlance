import AppIntents
import QuotaGlanceCore

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = AccountEntityQuery()

    let id: UUID
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct AccountEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        allEntities()
    }

    private func allEntities() -> [AccountEntity] {
        guard let store = QuotaGlanceShared.snapshotStore(),
              let envelope = try? store.read()
        else {
            return []
        }
        return envelope.accounts.map {
            AccountEntity(id: $0.accountID, displayName: $0.displayName)
        }
    }
}

struct QuotaGlanceWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "QuotaGlance"
    static let description = IntentDescription("Choose an account or show all accounts.")

    @Parameter(title: "Account")
    var account: AccountEntity?

    init() {}

    init(account: AccountEntity?) {
        self.account = account
    }
}
