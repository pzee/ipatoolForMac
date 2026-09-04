// Localize-Swift — https://github.com/marmelroy/Localize-Swift
// Foundation core only (the upstream package also ships UIKit IBInspectable).

import Foundation

let LCLCurrentLanguageKey = "LCLCurrentLanguageKey"
let LCLDefaultLanguage = "en"
let LCLBaseBundle = "Base"
public let LCLLanguageChangeNotification = "LCLLanguageChangeNotification"

public func Localized(_ string: String) -> String {
    string.localized()
}

public func Localized(_ string: String, arguments: CVarArg...) -> String {
    String(format: string.localized(), arguments: arguments)
}

public func LocalizedPlural(_ string: String, argument: CVarArg) -> String {
    string.localizedPlural(argument)
}

public extension String {
    func localized() -> String {
        localized(using: nil, in: .main)
    }

    func localizedFormat(_ arguments: CVarArg...) -> String {
        String(format: localized(), arguments: arguments)
    }

    func localizedPlural(_ argument: CVarArg) -> String {
        NSString.localizedStringWithFormat(localized() as NSString, argument) as String
    }

    func commented(_ argument: String) -> String {
        self
    }

    func localized(in bundle: Bundle?) -> String {
        localized(using: nil, in: bundle)
    }

    func localized(using tableName: String?) -> String {
        localized(using: tableName, in: .main)
    }

    func localized(using tableName: String?, in bundle: Bundle?) -> String {
        let bundle = bundle ?? .main
        if let path = bundle.path(forResource: Localize.currentLanguage(), ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return languageBundle.localizedString(forKey: self, value: nil, table: tableName)
        }
        if let path = bundle.path(forResource: LCLBaseBundle, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return languageBundle.localizedString(forKey: self, value: nil, table: tableName)
        }
        return self
    }
}

open class Localize: NSObject {
    open class func availableLanguages(_ excludeBase: Bool = false) -> [String] {
        var languages = Bundle.main.localizations
        if excludeBase, let index = languages.firstIndex(of: "Base") {
            languages.remove(at: index)
        }
        return languages
    }

    open class func currentLanguage() -> String {
        if let current = UserDefaults.standard.string(forKey: LCLCurrentLanguageKey) {
            return current
        }
        return defaultLanguage()
    }

    open class func setCurrentLanguage(_ language: String) {
        let selected = availableLanguages().contains(language) ? language : defaultLanguage()
        guard selected != currentLanguage() else { return }
        UserDefaults.standard.set(selected, forKey: LCLCurrentLanguageKey)
        NotificationCenter.default.post(name: Notification.Name(rawValue: LCLLanguageChangeNotification), object: nil)
    }

    open class func defaultLanguage() -> String {
        guard let preferred = Bundle.main.preferredLocalizations.first else {
            return LCLDefaultLanguage
        }
        return availableLanguages().contains(preferred) ? preferred : LCLDefaultLanguage
    }

    open class func resetCurrentLanguageToDefault() {
        setCurrentLanguage(defaultLanguage())
    }

    open class func displayNameForLanguage(_ language: String) -> String {
        let locale = NSLocale(localeIdentifier: currentLanguage())
        return locale.displayName(forKey: .identifier, value: language) ?? ""
    }
}
