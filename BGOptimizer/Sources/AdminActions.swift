import Foundation

/// The few changes that need an administrator, and only when you have switched on "Administrator actions" in Settings.
///
/// How the password is handled: the app never sees it. Each change is handed to macOS (`osascript ... with administrator privileges`),
/// which shows its own password dialog (Touch ID or Apple Watch work too) and runs ONE fixed command as root. Nothing is
/// remembered, so the next change asks again. The command is built here from a name that has been checked, never from free text.
///
/// What it can do, and nothing more:
///  - move a third-party helper tool or kernel extension that looks unused into a backup folder (so it can be moved back)
///  - switch a third-party launch daemon off or on at the next start (`launchctl disable|enable system/<label>`)
/// It never touches macOS's own items (`com.apple.`), security tools, or this app.

enum AdminError: Error {
    case notAllowed(String)          // a translation key
    case failed(String)              // a translation key
}

enum AdminActions {
    static let kextDir = "/Library/Extensions"
    static let helperDir = "/Library/PrivilegedHelperTools"
    static let daemonDir = "/Library/LaunchDaemons"
    /// Directly under /Library, which only root can write. (/Library/Application Support is open to the admin group, so another program of
    /// yours could have swapped a folder there for a link and made the root move land somewhere else.)
    static let backupRoot = "/Library/BG Optimizer Removed Drivers"

    // MARK: quoting (the only way text gets into a command)

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func appleScriptQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// A file or label name we are willing to put in a command: plain characters only, not hidden, no folder separators.
    static func isPlainName(_ s: String) -> Bool {
        s.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._@+ -]{0,199}\z"#, options: .regularExpression) != nil      // \z, not $: $ also accepts a trailing newline
    }

    private static var ownID: String { Bundle.main.bundleIdentifier ?? "com.alexxxela.bgoptimizer" }

    private static func isProtected(_ name: String) -> Bool {
        name.lowercased().hasPrefix("com.apple.") || Policy.isSecurityTool(name) || name == ownID
    }

    // MARK: removing a driver file

    /// Only a helper tool or a kernel extension that has no maker app and is not waiting for anything. A system extension cannot be
    /// removed by an app (macOS needs System Settings or the maker's own app for that), so it is never offered.
    static func canRemove(_ item: DriverItem) -> Bool {
        guard item.path != nil, item.kind == .helperTool || item.kind == .kernelExtension else { return false }
        return item.status == .probablyUnused || item.status == .makerAppMissing
    }

    /// The one command to run as root, and the path it moves. Throws without anything changing if any rule is not met.
    static func removalCommand(for item: DriverItem, stamp: String, kextDir: String = AdminActions.kextDir,
                               helperDir: String = AdminActions.helperDir, daemonDir: String = AdminActions.daemonDir,
                               backupRoot: String = AdminActions.backupRoot) throws -> (command: String, path: String, backup: String) {
        let refuse = AdminError.notAllowed(trkey("That driver cannot be removed here."))
        guard canRemove(item), let path = item.path else { throw refuse }
        let fm = FileManager.default
        let dir = item.kind == .kernelExtension ? kextDir : helperDir
        let name = URL(fileURLWithPath: path).lastPathComponent
        // the path is exactly one level inside the expected folder, a real file (not a link to somewhere else), and the name is plain
        guard URL(fileURLWithPath: path).deletingLastPathComponent().path == dir, isPlainName(name), !isProtected(name),
              item.kind != .kernelExtension || name.hasSuffix(".kext"),
              (try? fm.destinationOfSymbolicLink(atPath: path)) == nil, fm.fileExists(atPath: path) else { throw refuse }
        guard stamp.range(of: #"\A[0-9]{8}-[0-9]{6}\z"#, options: .regularExpression) != nil else { throw refuse }

        let backup = backupRoot + "/" + stamp
        var steps = ["/bin/mkdir -p \(shellQuote(backup))"]
        if item.kind == .helperTool {
            let plist = daemonDir + "/" + name + ".plist"
            // stop the job and take its start-up file along, so launchd does not keep trying to start a tool that is gone
            steps.append("{ /bin/launchctl bootout \(shellQuote("system/" + name)) >/dev/null 2>&1; if [ -f \(shellQuote(plist)) ]; then /bin/mv \(shellQuote(plist)) \(shellQuote(backup + "/")); fi; }")
        }
        steps.append("/bin/mv \(shellQuote(path)) \(shellQuote(backup + "/"))")
        return (steps.joined(separator: " && "), path, backup)
    }

    static func stampNow(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Asks macOS for the password and runs the command. Returns whatever macOS answered; nothing is kept.
    static func runAsAdmin(_ command: String, prompt: String) -> ToolRunner.Result {
        let script = "do shell script \(appleScriptQuote(command)) with prompt \(appleScriptQuote(prompt)) with administrator privileges"
        return ToolRunner.run("/usr/bin/osascript", ["-e", script], timeout: 180)       // time to find your password
    }

    /// Moves the driver into the backup folder. Returns the folder it was moved to.
    /// The list is read again first: the verdict on the screen may be minutes old (the maker's app may have been installed since).
    static func removeDriver(_ item: DriverItem, rescan: () -> [DriverItem] = { DriverScanner.read().items }) throws -> String {
        guard let fresh = rescan().first(where: { $0.id == item.id && $0.path == item.path }) else {
            throw AdminError.notAllowed(trkey("That driver cannot be removed here."))
        }
        let plan = try removalCommand(for: fresh, stamp: stampNow())
        let result = runAsAdmin(plan.command, prompt: tr("BG Optimizer wants to move the driver “%@” out of the way.", item.name))
        guard !result.timedOut else { throw AdminError.failed(trkey("No password was given in time, so nothing changed.")) }
        // read it back: the file must be gone from where it was
        guard result.status == 0, !FileManager.default.fileExists(atPath: plan.path) else {
            throw AdminError.failed(trkey("Nothing changed: the password was not given, or macOS refused."))
        }
        return plan.backup
    }

    // MARK: switching a launch daemon

    static func daemonCommand(label: String, enable: Bool) throws -> String {
        guard isPlainName(label), !label.contains(" "), !isProtected(label) else { throw AdminError.notAllowed(trkey("That item cannot be changed here.")) }
        return "/bin/launchctl \(enable ? "enable" : "disable") \(shellQuote("system/" + label))"
    }

    /// Switch a third-party daemon off or on for the next start. It never stops what is running.
    static func setDaemonEnabled(label: String, plistPath: String, enable: Bool, daemonDir: String = AdminActions.daemonDir) throws {
        let command = try daemonCommand(label: label, enable: enable)
        // the plist is a real file directly inside the daemons folder and names this label
        guard URL(fileURLWithPath: plistPath).deletingLastPathComponent().path == daemonDir,
              (try? FileManager.default.destinationOfSymbolicLink(atPath: plistPath)) == nil,
              let data = FileManager.default.contents(atPath: plistPath),
              let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              d["Label"] as? String == label,
              !Policy.isSecurityTool((d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first ?? "")) else {
            throw AdminError.notAllowed(trkey("That item cannot be changed here."))
        }
        let result = runAsAdmin(command, prompt: tr("BG Optimizer wants to change whether “%@” starts by itself.", label))
        guard !result.timedOut else { throw AdminError.failed(trkey("No password was given in time, so nothing changed.")) }
        let state = StartupParsers.parsePrintDisabled(StartupReaderShell.run("/bin/launchctl", ["print-disabled", "system"]))[label]
        guard result.status == 0, state == !enable else {
            throw AdminError.failed(trkey("Nothing changed: the password was not given, or macOS refused."))
        }
    }
}
