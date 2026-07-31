import Foundation

public enum ErrorPresenter {
    public static func message(
        for error: any Error,
        language: AppLanguage = .english
    ) -> String {
        switch error {
        case AccountValidationError.emptyDisplayName:
            L10n.string(.errorEmptyDisplayName, language: language)
        case AccountValidationError.emptyAPIKey:
            L10n.string(.errorEmptyAPIKey, language: language)
        case AccountValidationError.maximumAccountsReached:
            L10n.string(
                .errorMaximumAccounts,
                language: language,
                AccountValidator.maximumAccountCount
            )
        case AccountValidationError.duplicateDisplayName:
            L10n.string(.errorDuplicateDisplayName, language: language)
        case AccountValidationError.invalidThreshold:
            L10n.string(.errorInvalidThreshold, language: language)
        case AccountValidationError.replacementKeyRequired:
            L10n.string(.errorReplacementKeyRequired, language: language)
        case ProviderError.invalidCredential, ProviderError.providerInactive:
            L10n.string(.errorInvalidCredential, language: language)
        case ProviderError.rateLimited:
            L10n.string(.errorRateLimited, language: language)
        case let ProviderError.httpStatus(statusCode):
            L10n.string(.errorHTTPStatus, language: language, statusCode)
        case ProviderError.unsupportedCredential:
            L10n.string(.errorUnsupportedCredential, language: language)
        case ProviderError.regionDetectionFailed:
            L10n.string(.errorRegionDetectionFailed, language: language)
        case ProviderError.profileMismatch:
            L10n.string(.errorProfileMismatch, language: language)
        case ProviderError.invalidResponse:
            L10n.string(.errorInvalidResponse, language: language)
        case ProviderError.providerUnavailable:
            L10n.string(.errorProviderUnavailable, language: language)
        case CredentialStoreError.notFound:
            L10n.string(.errorCredentialNotFound, language: language)
        case CredentialStoreError.invalidData:
            L10n.string(.errorCredentialInvalidData, language: language)
        case CredentialStoreError.interactionRequired:
            L10n.string(.errorCredentialInteractionRequired, language: language)
        case let CredentialStoreError.unexpectedStatus(status):
            keychainMessage(for: status, language: language)
        case let urlError as URLError:
            networkMessage(for: urlError, language: language)
        default:
            L10n.string(.errorGeneric, language: language)
        }
    }
}

private extension ErrorPresenter {
    static func keychainMessage(
        for status: OSStatus,
        language: AppLanguage
    ) -> String {
        if status == -67068 {
            return L10n.string(.errorKeychainMissingBuild, language: language)
        }
        return L10n.string(.errorKeychainStatus, language: language, status)
    }

    static func networkMessage(
        for error: URLError,
        language: AppLanguage
    ) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            L10n.string(.errorNoInternet, language: language)
        case .timedOut:
            L10n.string(.errorTimedOut, language: language)
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            L10n.string(.errorHostUnreachable, language: language)
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            L10n.string(.errorSecureConnectionFailed, language: language)
        case .cancelled:
            L10n.string(.errorCancelled, language: language)
        default:
            L10n.string(
                .errorNetworkInterrupted,
                language: language,
                error.code.rawValue
            )
        }
    }
}
