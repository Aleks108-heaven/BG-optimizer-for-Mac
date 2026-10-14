import Foundation

/// "just now", "4 minutes ago" in the app's language. (RelativeDateTimeFormatter says "in 0 seconds" for something that happened a moment ago.)
func ago(_ date: Date) -> String {
    if Date().timeIntervalSince(date) < 10 { return tr("just now") }
    let f = RelativeDateTimeFormatter()
    f.locale = L10n.locale
    return f.localizedString(for: date, relativeTo: Date())
}

/// Text that comes from outside (a process name, a file name, a label) made safe to show and to log: control characters, line and
/// paragraph separators and invisible formatting characters (zero-width, right-to-left override) become a space, so a name cannot
/// forge a log line or disguise what it is (for example "gpj.exe" written backwards to look like a picture).
func plainText(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { u in
        switch u.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return " "
        default: return u
        }
    }))
}
