import Foundation

enum Verdict {
    case never        // hard-protected: silently skipped, no override
    case leaveAlone   // interactive / media apps: reported, never slowed
    case ok
}

/// Who may be slowed down. Names are matched against the path components of the executable
/// (so "Google Chrome Helper (Renderer)" inside Google Chrome.app matches "google chrome").
enum Policy {
    private static let aiHosts = ["lm studio", "lms", "llama-server", "llama.cpp", "llama-cli", "ollama", "koboldcpp", "jan"]
    private static let systemNames = [
        "windowserver", "loginwindow", "finder", "dock", "systemuiserver", "kernel_task", "launchd",
        "coreaudiod", "bluetoothd", "backupd", "cloudd", "bird", "fileproviderd", "controlcenter",
        "notificationcenter", "sshd", "coreservicesd", "bgoptimizer",
    ]
    private static let securityTools = [
        "crowdstrike", "falcon", "sentinel", "sophos", "eset", "malwarebytes", "kaspersky", "norton",
        "mcafee", "bitdefender", "veeam", "acronis", "jamf", "little snitch", "carbon black", "wdav",
        "microsoft defender", "avast",
    ]
    /// Interactive or media apps: reported, never slowed. The label is shown in the Activity window.
    private static let leaveAloneGroups: [(label: String, names: [String])] = [
        (trkey("Browser"), ["microsoft edge", "google chrome", "safari", "firefox", "brave browser", "arc", "opera", "vivaldi"]),
        (trkey("Call or meeting app"), ["zoom.us", "slack", "microsoft teams", "facetime", "discord"]),
        (trkey("Music or video app"), ["spotify", "music", "vlc", "quicktime player", "obs", "voicemeeter"]),
        (trkey("Editor or terminal"), ["visual studio code", "code", "cursor", "xcode", "terminal", "iterm", "iterm2", "ghostty", "warp",
                                     "intellij idea", "pycharm", "webstorm", "sublime text", "claude"]),
    ]
    /// Apple background workers that run as the user and are safe to slow even though they live under /System.
    private static let systemWorkersOK: Set<String> = ["mdworker_shared", "mdworker", "photoanalysisd", "mediaanalysisd"]
    private static let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/").map { $0.lowercased().replacingOccurrences(of: ".app", with: "") }
    }

    private static func matches(_ comps: [String], _ names: [String]) -> Bool {
        comps.contains { c in names.contains { c == $0 || c.hasPrefix($0 + " ") } }
    }

    /// The decision and a short reason a person can read.
    static func classify(path: String, extra: [String] = []) -> (verdict: Verdict, reason: String) {
        guard !path.isEmpty else { return (.never, trkey("Unknown process")) }
        let comps = components(path)
        let lower = path.lowercased()
        if matches(comps, extra) { return (.never, trkey("On your protected list")) }
        if matches(comps, aiHosts) { return (.never, trkey("Local AI host")) }
        if matches(comps, systemNames) { return (.never, trkey("System or this app")) }
        if looksLikeSecurityTool(lower) { return (.never, trkey("Security tool")) }
        if systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            return systemWorkersOK.contains(comps.last ?? "") ? (.ok, "") : (.never, trkey("System process"))
        }
        for group in leaveAloneGroups where matches(comps, group.names) { return (.leaveAlone, group.label) }
        if comps.contains(where: { $0.contains("audio") || $0.contains("sound") }) { return (.leaveAlone, trkey("Audio app")) }
        return (.ok, "")
    }

    /// Does a known name start a word in this lower-case text: at the very start, or right after anything that is not a letter or a digit
    /// ("/", ".", "-", "_", a space)? A plain substring test also found "eset" inside "updat-eSet-tings", "pr-eset" and "r-eset",
    /// so ordinary programs were taken for security tools.
    private static func startsWord(_ text: String, _ name: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: name, range: from..<text.endIndex) {
            if r.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: r.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    private static func looksLikeSecurityTool(_ lower: String) -> Bool {
        securityTools.contains { startsWord(lower, $0) }
    }

    /// Is this text (a label, a path, a name) a known security tool? Used to keep them out of every kind of change.
    static func isSecurityTool(_ text: String) -> Bool {
        looksLikeSecurityTool(text.lowercased())
    }

    /// The name "Never slow this app" adds to your list: the outermost app in the path ("Google Chrome" for all its helpers),
    /// or the program's own name when it is not inside an app.
    static func appName(path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return parts.last ?? path
    }

    /// The entry on your list (lower case) that protects this process, if there is one.
    static func matchedUserEntry(path: String, extra: [String]) -> String? {
        guard !path.isEmpty else { return nil }
        let comps = components(path)
        return extra.first { name in matches(comps, [name]) }
    }

    static func verdict(path: String, extra: [String] = []) -> Verdict {
        classify(path: path, extra: extra).verdict
    }
}
