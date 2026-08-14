import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("App language and L10n")
struct AppLanguageTests {
    @Test("System preference follows preferred languages")
    func systemPreferenceFollowsPreferredLanguages() {
        #expect(
            AppLanguage.resolve(
                preference: .system,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .chinese
        )
        #expect(
            AppLanguage.resolve(
                preference: .system,
                preferredLanguages: ["en-US"]
            ) == .english
        )
        #expect(
            AppLanguage.resolve(
                preference: .chinese,
                preferredLanguages: ["en-US"]
            ) == .chinese
        )
    }

    @Test("Chinese catalog covers settings and errors")
    func chineseCatalogCoversSettingsAndErrors() {
        #expect(
            L10n.string(.addAccount, language: .chinese) == "添加账户"
        )
        #expect(
            L10n.string(.errorEmptyAPIKey, language: .chinese) == "请输入 API 密钥。"
        )
        #expect(
            ErrorPresenter.message(
                for: AccountValidationError.emptyDisplayName,
                language: .chinese
            ) == "请输入账户名称。"
        )
    }

    @Test("Legacy preferences decode with system language default")
    func legacyPreferencesDecodeWithSystemLanguageDefault() throws {
        let data = Data(#"""
        {
          "refreshInterval": 300,
          "launchAtLogin": false
        }
        """#.utf8)
        let preferences = try JSONDecoder.quotaGlance.decode(
            AppPreferences.self,
            from: data
        )
        #expect(preferences.preferredLanguage == .system)
        #expect(preferences.preferredTheme == .system)
    }

    @Test("Theme labels are localized")
    func themeLabelsAreLocalized() {
        #expect(
            L10n.themePreferenceTitle(.system, language: .english) == "System"
        )
        #expect(
            L10n.themePreferenceTitle(.light, language: .chinese) == "浅色"
        )
        #expect(
            L10n.themePreferenceTitle(.dark, language: .chinese) == "深色"
        )
    }
}
