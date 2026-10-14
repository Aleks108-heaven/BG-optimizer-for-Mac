import Foundation

/// Programs that start when you log in or when the Mac boots: what they are, and whether you may switch them here.
///
/// What a normal app may change on macOS, and nothing more:
///  - agents in YOUR OWN ~/Library/LaunchAgents: `launchctl disable|enable gui/<uid>/<label>` (no password, survives restarts, reversible)
///  - everything else (system-wide agents and daemons, login-item apps) needs an administrator or System Settings: shown, not changed.
/// Switching an item off means "do not start it at the next login". It never stops or deletes anything that is running now.

enum StartupKind { case userAgent, systemAgent, systemDaemon, loginItem }

enum StartupControl {
    case toggle                      // you can switch it here
    case settingsOnly(String)        // use System Settings; the text (a translation key) says why
    case locked(String)              // never changed by this app; the text (a translation key) says why
}

struct StartupItem: Identifiable {
    let label: String
    let name: String
    let developer: String?
    let kind: StartupKind
    let startsWhen: String           // a translation key: "At login", "On a schedule", ...
    var enabled: Bool?               // will it start by itself? nil = unknown
    let running: Bool?               // is a process of it running now? nil = cannot tell
    let control: StartupControl
    let plistPath: String?
    var id: String { "\(kind)-\(label)" }

    var kindRank: Int {
        switch kind { case .userAgent: return 0; case .systemAgent: return 1; case .systemDaemon: return 2; case .loginItem: return 3 }
    }
}

/// One record of `sfltool dumpbtm` (the list behind System Settings > General > Login Items & Extensions).
struct BTMRecord {
    var name: String?
    var developer: String?
    var type: String = ""
    var identifier: String?
    var executable: String?
    var allowed: Bool?               // the switch in System Settings
}

enum StartupError: Error {
    case notAllowed(String)          // a translation key
    case failed(String)              // a translation key
}

// MARK: - parsing (pure functions, tested with fixed text)

enum StartupParsers {
    static func parsePrintDisabled(_ text: String) -> [String: Bool] {
        var out: [String: Bool] = [:]
        guard let re = try? NSRegularExpression(pattern: #""([^"]+)"\s*=>\s*(disabled|enabled|true|false)"#) else { return out }
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let l = Range(m.range(at: 1), in: s), let v = Range(m.range(at: 2), in: s) else { continue }
            out[String(s[l])] = ["disabled", "true"].contains(String(s[v]))      // true = switched off
        }
        return out
    }

    /// label -> process id (nil when loaded but not running)
    static func parseLaunchList(_ text: String) -> [String: Int32?] {
        var out: [String: Int32?] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, cols[0] != "PID" else { continue }
            out[cols[2]] = Int32(cols[0])
        }
        return out
    }

    static func parseBTM(_ text: String) -> [BTMRecord] {
        var out: [BTMRecord] = []
        var cur: BTMRecord?
        func clean(_ v: String) -> String? { v == "(null)" || v.isEmpty ? nil : v }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.range(of: #"^#\d+:"#, options: .regularExpression) != nil {
                if let c = cur { out.append(c) }
                cur = BTMRecord()
                continue
            }
            guard cur != nil, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "Name": cur?.name = clean(value)
            case "Developer Name": cur?.developer = clean(value)
            case "Type": cur?.type = value.components(separatedBy: " (0x").first ?? value
            case "Identifier": cur?.identifier = clean(value)
            case "Executable Path": cur?.executable = clean(value)
            case "Disposition":
                // "[enabled, allowed, notified] (0xb)": "allowed" is the System Settings switch. ("disallowed" is a different word.)
                if let a = value.firstIndex(of: "["), let b = value.firstIndex(of: "]") {
                    let tokens = value[value.index(after: a)..<b].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    cur?.allowed = tokens.contains("allowed")
                }
            default: break
            }
        }
        if let c = cur { out.append(c) }
        return out
    }

    /// "16.com.example.helper" -> "com.example.helper"
    static func labelFromBTMIdentifier(_ id: String) -> String {
        if let dot = id.firstIndex(of: "."), id[..<dot].allSatisfy({ $0.isNumber }) { return String(id[id.index(after: dot)...]) }
        return id
    }
}

// MARK: - reading

struct AgentPlist {
    let label: String
    let path: String
    let program: String?
    let startsWhen: String
    let plistDisabled: Bool
}

enum StartupReader {
    static let userAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path

    /// When does it start? From the keys in the plist.
    static func startsWhen(_ d: [String: Any]) -> String {
        func truthy(_ v: Any?) -> Bool { (v as? Bool) ?? (v is [String: Any]) }
        let atLogin = (d["RunAtLoad"] as? Bool) == true
        let kept = truthy(d["KeepAlive"])
        let scheduled = d["StartInterval"] != nil || d["StartCalendarInterval"] != nil
        if atLogin && kept { return trkey("At login, kept running") }
        if atLogin && scheduled { return trkey("At login, then on a schedule") }
        if atLogin { return trkey("At login") }
        if kept { return trkey("Kept running") }
        if scheduled { return trkey("On a schedule") }
        return trkey("On demand")
    }

    static func scan(_ dir: String) -> [AgentPlist] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [AgentPlist] = []
        for f in files.sorted() where f.hasSuffix(".plist") {
            let path = dir + "/" + f
            guard let data = FileManager.default.contents(atPath: path),
                  let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let label = d["Label"] as? String else { continue }
            let program = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
            out.append(AgentPlist(label: label, path: path, program: program, startsWhen: startsWhen(d), plistDisabled: (d["Disabled"] as? Bool) == true))
        }
        return out
    }

    /// `sfltool` can be slow, or wait forever where there is no desktop session, so it gets longer than the others but not unlimited.
    private static func run(_ tool: String, _ args: [String]) -> String {
        ToolRunner.run(tool, args, timeout: tool == "/usr/bin/sfltool" ? 20 : 8).output
    }

    static func isSecurityTool(_ text: String) -> Bool { Policy.isSecurityTool(text) }

    /// Everything that starts by itself, apart from macOS's own items. Takes a few seconds (sfltool), so call it off the main thread.
    static func read(userAgentsDir: String = StartupReader.userAgentsDir) -> [StartupItem] {
        let uid = getuid()
        let disabledUser = StartupParsers.parsePrintDisabled(run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]))
        let disabledSystem = StartupParsers.parsePrintDisabled(run("/bin/launchctl", ["print-disabled", "system"]))
        let running = StartupParsers.parseLaunchList(run("/bin/launchctl", ["list"]))
        let btm = StartupParsers.parseBTM(run("/usr/bin/sfltool", ["dumpbtm"]))
        var btmByLabel: [String: BTMRecord] = [:]
        for r in btm { if let id = r.identifier { btmByLabel[StartupParsers.labelFromBTMIdentifier(id)] = r } }
        let ownID = Bundle.main.bundleIdentifier ?? "com.alexxxela.bgoptimizer"

        var items: [StartupItem] = []
        var seen = Set<String>()
        let sources: [(String, StartupKind)] = [(userAgentsDir, .userAgent), ("/Library/LaunchAgents", .systemAgent), ("/Library/LaunchDaemons", .systemDaemon)]
        for (dir, kind) in sources {
            for a in scan(dir) where !a.label.hasPrefix("com.apple.") {
                let rec = btmByLabel[a.label]
                let name = plainText(displayName(btmName: rec?.name, program: a.program, label: a.label))
                let disabledByLaunchd = (kind == .systemDaemon ? disabledSystem : disabledUser)[a.label] == true
                let allowed = rec?.allowed
                let enabled: Bool? = kind == .userAgent ? !(disabledByLaunchd || a.plistDisabled || allowed == false)
                                                         : (allowed.map { $0 && !disabledByLaunchd })
                let control: StartupControl
                if a.label == ownID { control = .locked(trkey("This app: use Launch at login in Settings")) }
                else if isSecurityTool(a.label + " " + (a.program ?? "") + " " + name) { control = .locked(trkey("Security tool")) }
                else if kind == .userAgent && allowed == false { control = .settingsOnly(trkey("Switched off in System Settings: turn it back on there")) }
                else if kind == .userAgent { control = .toggle }
                else { control = .settingsOnly(trkey("Needs an administrator: use System Settings")) }
                let isRunning: Bool? = kind == .userAgent ? (running[a.label].map { $0 != nil } ?? false) : nil
                items.append(StartupItem(label: a.label, name: name, developer: rec?.developer, kind: kind, startsWhen: a.startsWhen,
                                         enabled: enabled, running: isRunning, control: control, plistPath: a.path))
                seen.insert(a.label)
            }
        }
        // Apps registered as login items (no plist of their own): shown, managed in System Settings.
        for r in btm where r.type == "app" || r.type == "login item" {
            guard let id = r.identifier else { continue }
            let label = StartupParsers.labelFromBTMIdentifier(id)
            guard !seen.contains(label), !label.hasPrefix("com.apple.") else { continue }
            let name = plainText(r.name ?? label)
            let control: StartupControl = label == ownID ? .locked(trkey("This app: use Launch at login in Settings"))
                : (isSecurityTool(label + " " + name) ? .locked(trkey("Security tool")) : .settingsOnly(trkey("Managed in System Settings")))
            items.append(StartupItem(label: label, name: name, developer: r.developer, kind: .loginItem, startsWhen: trkey("At login"),
                                     enabled: r.allowed, running: nil, control: control, plistPath: nil))
        }
        return items.sorted { ($0.kindRank, $0.name.lowercased()) < ($1.kindRank, $1.name.lowercased()) }
    }

    /// A readable name: the name System Settings shows, else the app the program lives in, else the label.
    static func displayName(btmName: String?, program: String?, label: String) -> String {
        if let n = btmName, n != label, !n.hasPrefix("com."), !n.contains(".") { return n }
        if let p = program, !p.isEmpty {
            let n = Policy.appName(path: p)
            if !n.isEmpty, !["sh", "bash", "zsh", "env", "python3", "python", "node"].contains(n) { return n }
        }
        return label
    }
}

// MARK: - changing (only your own agents; every check is made again here)

enum StartupControlAction {
    /// Switch an agent in your own Library on or off for the next login. Throws without changing anything if any rule is not met.
    static func setEnabled(label: String, plistPath: String, enable: Bool,
                           agentsDir: String = StartupReader.userAgentsDir, uid: uid_t = getuid()) throws {
        // 1. the label is plain text
        guard label.range(of: #"^[A-Za-z0-9._@+-]{1,200}$"#, options: .regularExpression) != nil else { throw StartupError.notAllowed(trkey("That item cannot be changed here.")) }
        // 2. never macOS itself, security tools, or this app
        if label.hasPrefix("com.apple.") || StartupReader.isSecurityTool(label) || label == (Bundle.main.bundleIdentifier ?? "com.alexxxela.bgoptimizer") {
            throw StartupError.notAllowed(trkey("That item cannot be changed here."))
        }
        // 3. the plist is a real file inside YOUR LaunchAgents folder (symbolic links are resolved first), and names this label
        let dir = URL(fileURLWithPath: agentsDir).resolvingSymlinksInPath().path
        let file = URL(fileURLWithPath: plistPath).resolvingSymlinksInPath().path
        guard file.hasPrefix(dir + "/"),
              let data = FileManager.default.contents(atPath: file),
              let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              d["Label"] as? String == label else { throw StartupError.notAllowed(trkey("That item cannot be changed here.")) }
        guard !StartupReader.isSecurityTool((d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first ?? "")) else {
            throw StartupError.notAllowed(trkey("That item cannot be changed here."))
        }
        // 4. launchd does the work. "disable" only prevents the next start; it does not stop or delete anything.
        let target = "gui/\(uid)/\(label)"
        let result = ToolRunner.run("/bin/launchctl", [enable ? "enable" : "disable", target], timeout: 8)
        guard !result.timedOut else { throw StartupError.failed(trkey("macOS did not accept the change.")) }
        // 5. read it back
        let state = StartupParsers.parsePrintDisabled(StartupReaderShell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]))[label]
        guard result.status == 0, state == !enable else { throw StartupError.failed(trkey("macOS did not accept the change.")) }
    }
}

/// Small shared helper (kept separate so the reader's private runner stays private).
enum StartupReaderShell {
    static func run(_ tool: String, _ args: [String]) -> String {
        ToolRunner.run(tool, args, timeout: 8).output
    }
}
