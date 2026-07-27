import Foundation

public struct AccountDraft: Equatable, Sendable {
    public var displayName: String
    public var apiKey: String
    public var provider: ProviderID
    public var baseURLText: String
    public var isEnabled: Bool
    public var lowBalanceThresholdText: String

    public init(
        displayName: String = "",
        apiKey: String = "",
        provider: ProviderID = .apiInfo,
        baseURLText: String = "",
        isEnabled: Bool = true,
        lowBalanceThresholdText: String = ""
    ) {
        self.displayName = displayName
        self.apiKey = apiKey
        self.provider = provider
        self.baseURLText = baseURLText
        self.isEnabled = isEnabled
        self.lowBalanceThresholdText = lowBalanceThresholdText
    }
}

public struct ValidatedAccountDraft: Equatable, Sendable {
    public var displayName: String
    public var apiKey: String?
    public var provider: ProviderID
    public var providerConfiguration: ProviderConfiguration?
    public var isEnabled: Bool
    public var lowBalanceThreshold: Decimal?

    public init(
        displayName: String,
        apiKey: String?,
        provider: ProviderID = .apiInfo,
        providerConfiguration: ProviderConfiguration? = nil,
        isEnabled: Bool,
        lowBalanceThreshold: Decimal?
    ) {
        self.displayName = displayName
        self.apiKey = apiKey
        self.provider = provider
        self.providerConfiguration = providerConfiguration
        self.isEnabled = isEnabled
        self.lowBalanceThreshold = lowBalanceThreshold
    }
}

public enum AccountValidationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case emptyAPIKey
    case maximumAccountsReached
    case duplicateDisplayName
    case invalidThreshold
    case replacementKeyRequired
}

public enum AccountValidator {
    public static let maximumAccountCount = 20

    public static func validate(
        draft: AccountDraft,
        existingAccounts: [Account],
        editingAccountID: UUID? = nil
    ) throws -> ValidatedAccountDraft {
        if editingAccountID == nil,
           existingAccounts.count >= maximumAccountCount {
            throw AccountValidationError.maximumAccountsReached
        }

        let displayName = draft.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !displayName.isEmpty else {
            throw AccountValidationError.emptyDisplayName
        }

        let apiKeyText = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String?
        if apiKeyText.isEmpty {
            guard editingAccountID != nil else {
                throw AccountValidationError.emptyAPIKey
            }
            if let editingAccount = existingAccounts.first(where: {
                $0.id == editingAccountID
            }), editingAccount.provider != draft.provider {
                throw AccountValidationError.replacementKeyRequired
            }
            apiKey = nil
        } else {
            apiKey = apiKeyText
        }

        let normalizedName = displayName.lowercased()
        let hasDuplicate = existingAccounts.contains { account in
            account.id != editingAccountID
                && account.displayName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == normalizedName
        }
        guard !hasDuplicate else {
            throw AccountValidationError.duplicateDisplayName
        }

        let thresholdText = draft.lowBalanceThresholdText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let threshold: Decimal?
        if thresholdText.isEmpty {
            threshold = nil
        } else if let value = Decimal(
            string: thresholdText,
            locale: Locale(identifier: "en_US_POSIX")
        ), value >= 0 {
            threshold = value
        } else {
            throw AccountValidationError.invalidThreshold
        }

        let providerConfiguration: ProviderConfiguration?
        if draft.provider == .bailian {
            providerConfiguration = ProviderConfiguration(
                baseURL: try BailianEndpoint.normalizedBaseURL(from: draft.baseURLText)
            )
        } else {
            providerConfiguration = nil
        }

        return ValidatedAccountDraft(
            displayName: displayName,
            apiKey: apiKey,
            provider: draft.provider,
            providerConfiguration: providerConfiguration,
            isEnabled: draft.isEnabled,
            lowBalanceThreshold: threshold
        )
    }
}
