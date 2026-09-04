import Foundation

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case en

    private static let defaultsKey = "appLanguage"

    var title: String {
        switch self {
        case .system: return L10n.languageSystem
        case .zhHans: return L10n.languageChinese
        case .en: return L10n.languageEnglish
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    static func apply() {
        switch current {
        case .system:
            UserDefaults.standard.removeObject(forKey: LCLCurrentLanguageKey)
        case .zhHans, .en:
            Localize.setCurrentLanguage(current.rawValue)
        }
    }

    static func select(_ language: AppLanguage) {
        guard language != current else { return }
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        apply()
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}
