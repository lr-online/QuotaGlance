import Foundation

public enum AppLanguagePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case chinese

    public var id: String { rawValue }
}

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case chinese

    public var locale: Locale {
        switch self {
        case .english:
            Locale(identifier: "en_US")
        case .chinese:
            Locale(identifier: "zh_CN")
        }
    }

    public static func resolve(
        preference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        switch preference {
        case .english:
            return .english
        case .chinese:
            return .chinese
        case .system:
            let primary = preferredLanguages.first?
                .replacingOccurrences(of: "_", with: "-")
                .lowercased() ?? "en"
            if primary.hasPrefix("zh") {
                return .chinese
            }
            return .english
        }
    }
}
