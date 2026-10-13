import Foundation

/// The language choice you can make in Settings. "System default" follows your Mac's language list.
enum AppLanguage: String, Codable, CaseIterable {
    case system, english = "en", ukrainian = "uk"
}

/// Text lookup that can switch language while the app runs (no restart).
/// Strings live in Resources/<code>.lproj/App.strings. The key is the English text; a missing translation shows the key.
/// The table is called "App" (not "Localizable") on purpose, so SwiftUI does not translate literals behind our back.
enum L10n {
    private static let lock = NSLock()
    private static var _code = "en"
    private static var _bundle: Bundle?

    static var code: String { lock.lock(); defer { lock.unlock() }; return _code }
    static var locale: Locale { Locale(identifier: code) }

    /// Which of our languages a choice means right now.
    static func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "en"
        case .ukrainian: return "uk"
        case .system:
            for id in Locale.preferredLanguages {
                if id.hasPrefix("uk") { return "uk" }
                if id.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }

    static func apply(_ language: AppLanguage) {
        let resolved = resolve(language)
        let bundle = Bundle.main.path(forResource: resolved, ofType: "lproj").flatMap { Bundle(path: $0) }
        lock.lock(); _code = resolved; _bundle = bundle; lock.unlock()
    }

    static func string(_ key: String) -> String {
        lock.lock(); let b = _bundle; lock.unlock()
        return b?.localizedString(forKey: key, value: key, table: "App") ?? key
    }

    /// CLDR plural category. English: one/other. Ukrainian: one/few/many.
    static func category(_ n: Int, code: String) -> String {
        if code == "uk" {
            let m10 = n % 10, m100 = n % 100
            if m10 == 1 && m100 != 11 { return "one" }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return "few" }
            return "many"
        }
        return n == 1 ? "one" : "other"
    }
}

/// Translate. Pass format arguments for %d / %@ (Ukrainian may reorder them with %1$d, %2$@).
func tr(_ key: String, _ args: CVarArg...) -> String {
    let text = L10n.string(key)
    return args.isEmpty ? text : String(format: text, locale: L10n.locale, arguments: args)
}

/// Translate a phrase that depends on a number: looks up "<base>.one", ".few", ".many" or ".other". The number is the first argument.
func trPlural(_ base: String, _ n: Int, _ extra: CVarArg...) -> String {
    let wanted = base + "." + L10n.category(n, code: L10n.code)
    var text = L10n.string(wanted)
    if text == wanted { text = L10n.string(base + ".other") }
    return String(format: text, locale: L10n.locale, arguments: [n] + extra)
}

/// Marks a string as a translation key without translating it now (the string is translated later, where it is shown).
/// tools/check_strings.py reads these markers, so keys used this way are checked too.
func trkey(_ key: String) -> String { key }
