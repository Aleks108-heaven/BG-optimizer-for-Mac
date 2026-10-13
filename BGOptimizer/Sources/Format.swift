import Foundation

/// "just now", "4 minutes ago" in the app's language. (RelativeDateTimeFormatter says "in 0 seconds" for something that happened a moment ago.)
func ago(_ date: Date) -> String {
    if Date().timeIntervalSince(date) < 10 { return tr("just now") }
    let f = RelativeDateTimeFormatter()
    f.locale = L10n.locale
    return f.localizedString(for: date, relativeTo: Date())
}
