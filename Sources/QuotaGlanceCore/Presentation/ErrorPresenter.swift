import Foundation

public enum ErrorPresenter {
    public static func message(for error: any Error) -> String {
        switch error {
        case AccountValidationError.emptyDisplayName:
            "Enter an account name."
        case AccountValidationError.emptyAPIKey:
            "Enter an API key."
        case AccountValidationError.maximumAccountsReached:
            "QuotaGlance supports up to \(AccountValidator.maximumAccountCount) accounts."
        case AccountValidationError.duplicateDisplayName:
            "Account names must be unique."
        case AccountValidationError.invalidThreshold:
            "Enter a valid non-negative threshold."
        case AccountValidationError.replacementKeyRequired:
            "Enter a replacement key when changing providers."
        case ProviderError.invalidCredential, ProviderError.providerInactive:
            "The provider rejected this key."
        case ProviderError.rateLimited:
            "The provider is rate limiting requests. Try again later."
        case let ProviderError.httpStatus(statusCode):
            "The provider returned HTTP \(statusCode). Try again later."
        case ProviderError.unsupportedCredential:
            "MiniMax pay-as-you-go keys are not supported. Add a Token or Coding Plan subscription key."
        case ProviderError.regionDetectionFailed:
            "Neither official regional endpoint accepted this key. Check the key and try again."
        case ProviderError.profileMismatch:
            "The saved key type no longer matches this account. Replace the key to detect it again."
        case ProviderError.invalidResponse:
            "The provider returned an unexpected response."
        case ProviderError.providerUnavailable:
            "This provider is not available in this build."
        case CredentialStoreError.notFound:
            "The API key is missing from Keychain."
        case CredentialStoreError.invalidData:
            "The saved API key in Keychain is invalid. Replace the key and try again."
        case let CredentialStoreError.unexpectedStatus(status):
            keychainMessage(for: status)
        case let urlError as URLError:
            networkMessage(for: urlError)
        default:
            "The operation could not be completed."
        }
    }
}

private extension ErrorPresenter {
    static func keychainMessage(for status: OSStatus) -> String {
        if status == -67068 {
            return "QuotaGlance could not access Keychain because this app build is no longer on disk. Quit and reopen the installed app, then try again."
        }
        return "QuotaGlance could not access Keychain (status \(status)). Reopen the app and try again."
    }

    static func networkMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            "No internet connection is available. Check the network and try again."
        case .timedOut:
            "The provider request timed out. Try again later."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "The provider host could not be reached. Check the network and try again."
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            "A secure connection to the provider could not be established."
        case .cancelled:
            "The provider request was cancelled. Try again."
        default:
            "A network error interrupted the provider request (\(error.code.rawValue)). Try again."
        }
    }
}
