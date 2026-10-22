import AppKit
import Foundation

// Drivers: the extensions macOS keeps for third-party hardware and security software, and the root helper tools that apps
// leave behind. This only reads. Removing a driver needs an administrator, so the app never does it: it shows what it found
// and why a row looks unused. "Outdated" cannot be known without asking the maker over the network, which this app never
// does, so it shows the version or the date and leaves that judgement to you.

enum DriverKind: Int {
    case systemExtension, kernelExtension, helperTool
}

/// Most interesting first (this is also the sort order).
enum DriverStatus: Int {
    case probablyUnused     // switched off, and no app from its maker is installed
    case makerAppMissing    // no app from its maker is installed
    case switchedOff        // switched off, but an app from its maker is installed
    case pending            // waiting for your approval, or to be removed at the next restart
    case legacy             // a kernel extension: the old kind of driver
    case enabled            // on, and an app from its maker is installed
    case installed          // macOS does not say whether it is used
}

enum ExtensionState {
    case enabled, disabled, waitingForUser, removing, unknown
}

struct DriverItem: Identifiable, Equatable {
    let name: String
    let identifier: String
    let kind: DriverKind
    let info: String?           // the version, or the day it was installed
    let status: DriverStatus
    let detail: String          // a translation key: why it has this status
    let detailArg: String?      // fills the %@ of the detail (the maker)
    var id: String { "\(kind.rawValue)-\(identifier)" }
    var kindRank: Int { kind.rawValue }
    var statusRank: Int { status.rawValue }
}

/// What the scan found, and whether the list of system extensions could be read at all.
struct DriverReadout {
    var items: [DriverItem]
    var extensionsRead: Bool
}

struct SystemExtensionRecord: Equatable {
    var category: String
    var team: String
    var identifier: String
    var version: String?
    var name: String
    var state: ExtensionState
}

// MARK: - parsing (pure functions, tested with fixed text)

enum DriverParsers {
    /// "[activated enabled]", "[activated disabled]", "[activated waiting for user]", "[terminated waiting to uninstall on reboot]"
    static func parseState(_ text: String) -> ExtensionState {
        let s = text.lowercased()
        if s.contains("terminated") || s.contains("uninstall") { return .removing }
        if s.contains("waiting for user") { return .waitingForUser }
        if s.contains("disabled") { return .disabled }
        if s.contains("enabled") { return .enabled }
        return .unknown
    }

    /// `systemextensionsctl list`: a "---" line names the kind, then one tab-separated row per extension:
    /// enabled, active, team, "bundle id (version)", name, "[state]".
    static func parseSystemExtensions(_ text: String) -> [SystemExtensionRecord] {
        var out: [SystemExtensionRecord] = []
        var category = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("---") {
                let first = line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
                category = first.replacingOccurrences(of: "com.apple.system_extension.", with: "")
                continue
            }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 6, cols[0] != "enabled" else { continue }
            var identifier = cols[3]
            var version: String?
            if let open = identifier.range(of: " ("), identifier.hasSuffix(")") {
                version = String(identifier[open.upperBound...].dropLast()).components(separatedBy: "/").first
                identifier = String(identifier[..<open.lowerBound])
            }
            guard !identifier.isEmpty else { continue }
            out.append(SystemExtensionRecord(category: category, team: cols[2], identifier: identifier, version: version,
                                              name: cols[4], state: parseState(cols[5])))
        }
        return out
    }
}

// MARK: - the decision and the scan

enum DriverScanner {
    static let detailProbablyUnused = trkey("Off, and no “%@” app is installed.")
    static let detailMakerMissing = trkey("No “%@” app is installed.")
    static let detailSwitchedOff = trkey("Off. A “%@” app is installed.")
    static let detailWaiting = trkey("Waiting for your approval in System Settings.")
    static let detailRemoving = trkey("Will be removed at the next restart.")
    static let detailLegacy = trkey("A kernel extension: the old kind of driver.")
    static let detailEnabled = trkey("On. A “%@” app is installed.")
    static let detailInstalled = trkey("From “%@”. macOS does not show if it is used.")
    static let detailUnknownState = trkey("macOS did not say whether it is on.")
    static let detailNoMaker = trkey("macOS does not say who installed it.")

    struct Verdict {
        let status: DriverStatus
        let detail: String
        let arg: String?
    }

    /// The maker of a bundle identifier ("com.malwarebytes.mbam.engine" -> "malwarebytes"). The same rule as the Storage tab.
    static func maker(_ id: String) -> String { StorageScanner.vendorToken(id) }

    /// Why a row has its status. `makerPresent` is whether any app from the same maker is installed; `nil` when the name says nothing about a maker.
    static func classify(kind: DriverKind, state: ExtensionState?, maker: String?, makerPresent: Bool?) -> Verdict {
        switch state {
        case .removing?: return Verdict(status: .pending, detail: detailRemoving, arg: nil)
        case .waitingForUser?: return Verdict(status: .pending, detail: detailWaiting, arg: nil)
        case .disabled?:
            guard let m = maker, let present = makerPresent else { return Verdict(status: .switchedOff, detail: detailUnknownState, arg: nil) }
            return present ? Verdict(status: .switchedOff, detail: detailSwitchedOff, arg: m)
                           : Verdict(status: .probablyUnused, detail: detailProbablyUnused, arg: m)
        default: break
        }
        guard let m = maker, let present = makerPresent else { return Verdict(status: .installed, detail: detailNoMaker, arg: nil) }
        if !present { return Verdict(status: .makerAppMissing, detail: detailMakerMissing, arg: m) }
        switch kind {
        case .kernelExtension: return Verdict(status: .legacy, detail: detailLegacy, arg: nil)
        case .helperTool: return Verdict(status: .installed, detail: detailInstalled, arg: m)
        case .systemExtension:
            return state == .enabled ? Verdict(status: .enabled, detail: detailEnabled, arg: m)
                                     : Verdict(status: .installed, detail: detailUnknownState, arg: nil)
        }
    }

    /// A version comes from the maker's own files, so it is shown as plain text and kept short (like names, see `plainText`).
    private static func versionText(_ s: String?) -> String? {
        guard let s = s else { return nil }
        let t = String(plainText(s).prefix(40)).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private static func day(_ d: Date?) -> String? {
        guard let d = d else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func modified(_ path: String) -> String? {
        day((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)
    }

    /// Everything the three sources list, most interesting first. `installedIDs` are the bundle identifiers of installed apps;
    /// `appExists` asks macOS whether an app with an exact identifier exists anywhere (an app can live outside the usual folders).
    static func scan(extensionList: String, kextDir: String, helperDir: String, installedIDs: Set<String>,
                     appExists: (String) -> Bool) -> [DriverItem] {
        let fm = FileManager.default
        let makers = Set(installedIDs.map { maker($0) })
        func present(_ id: String) -> Bool {
            if makers.contains(maker(id)) { return true }
            let parts = id.split(separator: ".").map(String.init)
            guard parts.count >= 3 else { return appExists(id) }
            return (3...parts.count).contains { appExists(parts[0..<$0].joined(separator: ".")) }
        }
        func shown(_ s: String) -> Bool { !s.isEmpty && plainText(s) == s && !s.lowercased().hasPrefix("com.apple.") }

        var items: [DriverItem] = []

        for r in DriverParsers.parseSystemExtensions(extensionList) where shown(r.identifier) {
            let m = maker(r.identifier)
            let v = classify(kind: .systemExtension, state: r.state, maker: m, makerPresent: present(r.identifier))
            items.append(DriverItem(name: plainText(r.name.isEmpty ? r.identifier : r.name), identifier: r.identifier, kind: .systemExtension,
                                    info: versionText(r.version), status: v.status, detail: v.detail, detailArg: v.arg))
        }

        for file in ((try? fm.contentsOfDirectory(atPath: kextDir)) ?? []).sorted() where file.hasSuffix(".kext") && !file.hasPrefix(".") {
            let path = kextDir + "/" + file
            guard let data = fm.contents(atPath: path + "/Contents/Info.plist"),
                  let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = d["CFBundleIdentifier"] as? String, shown(id) else { continue }
            let m = maker(id)
            let v = classify(kind: .kernelExtension, state: nil, maker: m, makerPresent: present(id))
            let name = plainText((d["CFBundleName"] as? String) ?? String(file.dropLast(5)))
            let version = (d["CFBundleShortVersionString"] as? String) ?? (d["CFBundleVersion"] as? String)
            items.append(DriverItem(name: name, identifier: id, kind: .kernelExtension, info: versionText(version) ?? modified(path),
                                    status: v.status, detail: v.detail, detailArg: v.arg))
        }

        for file in ((try? fm.contentsOfDirectory(atPath: helperDir)) ?? []).sorted() where !file.hasPrefix(".") && shown(file) {
            // Only a reverse-DNS name says who made it; any other name is listed without a verdict about its maker.
            let id = StorageScanner.baseIdentifier(file)
            let v = classify(kind: .helperTool, state: nil, maker: id.map { maker($0) }, makerPresent: id.map { present($0) })
            items.append(DriverItem(name: file, identifier: file, kind: .helperTool, info: modified(helperDir + "/" + file),
                                    status: v.status, detail: v.detail, detailArg: v.arg))
        }

        return items.sorted { ($0.statusRank, $0.name.lowercased()) < ($1.statusRank, $1.name.lowercased()) }
    }

    /// The real Mac. Takes a second or two (systemextensionsctl and a look through the Applications folders): call it off the main thread.
    static func read(kextDir: String = "/Library/Extensions", helperDir: String = "/Library/PrivilegedHelperTools") -> DriverReadout {
        let result = ToolRunner.run("/usr/bin/systemextensionsctl", ["list"], timeout: 15)
        let installed = StorageScanner.installedBundleIDs(home: FileManager.default.homeDirectoryForCurrentUser)
        let items = scan(extensionList: result.output, kextDir: kextDir, helperDir: helperDir, installedIDs: installed,
                         appExists: { !$0.isEmpty && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        return DriverReadout(items: items, extensionsRead: result.status == 0 && !result.timedOut)
    }
}
