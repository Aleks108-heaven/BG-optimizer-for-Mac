import AppKit
import Darwin
import Foundation

// Storage: lists what is taking space in YOUR OWN Library (app caches, app logs, Xcode build files) and what looks like
// the leftovers of apps you removed. It only reads. The one change it can make is "Move to Trash" for one item that you
// choose, after a confirmation, and every rule is checked again at that moment. Nothing is deleted, and nothing is
// cleaned automatically: the Trash keeps the item until you empty it, so it can be put back.

enum StorageKind: Int {
    case cache, log, developer, leftover
}

struct StorageItem: Identifiable, Equatable {
    var id: String { path }
    let name: String            // the folder or file name
    let path: String
    let kind: StorageKind
    var bytes: Int64?           // nil: not read (macOS keeps other apps' containers closed)
    var approximate = false     // the size scan stopped early, so the real size is at least this
    let note: String            // a translation key, shown in the Details column
    let noteArg: String?        // fills the %@ of the note
    let lock: String?           // a translation key: why it cannot be moved right now

    var sortBytes: Int64 { bytes ?? -1 }
    var kindRank: Int { kind.rawValue }
}

enum StorageError: Error {
    case notAllowed(String)     // a translation key
    case failed(String)
}

/// What the scan knows about this Mac: which apps are installed and which are running. Built from the system, or by hand in tests.
struct StorageContext {
    var home: URL
    var installedTokens: Set<String>        // vendor names of installed apps ("google", "microsoft", ...)
    var installedIDs: Set<String>           // exact bundle identifiers of installed apps, lower case
    var runningIDs: Set<String>             // bundle identifiers of running apps, lower case
    var runningWords: Set<String>           // folder and app names on the paths of running programs, lower case
    var appExists: (String) -> Bool = { _ in false }        // does macOS know an app with this exact identifier, wherever it is?
    var ownID = Bundle.main.bundleIdentifier ?? "com.alexxxela.bgoptimizer"
}

enum StorageScanner {
    struct Root {
        let sub: String             // below ~/Library
        let kind: StorageKind
        let sizeReadable: Bool      // false for other apps' sandbox containers
        let listsAnything: Bool     // false: only leftovers are listed from this folder, never plain files
    }

    /// The only places this feature ever looks at or changes: direct children of these folders in your own Library.
    static let roots: [Root] = [
        Root(sub: "Caches", kind: .cache, sizeReadable: true, listsAnything: true),
        Root(sub: "Logs", kind: .log, sizeReadable: true, listsAnything: true),
        Root(sub: "Developer/Xcode/DerivedData", kind: .developer, sizeReadable: true, listsAnything: true),
        Root(sub: "Application Support", kind: .leftover, sizeReadable: true, listsAnything: false),
        Root(sub: "Preferences", kind: .leftover, sizeReadable: true, listsAnything: false),
        Root(sub: "Saved Application State", kind: .leftover, sizeReadable: true, listsAnything: false),
        Root(sub: "HTTPStorages", kind: .leftover, sizeReadable: true, listsAnything: false),
        Root(sub: "Application Scripts", kind: .leftover, sizeReadable: true, listsAnything: false),
        Root(sub: "Containers", kind: .leftover, sizeReadable: false, listsAnything: false),
        Root(sub: "Group Containers", kind: .leftover, sizeReadable: false, listsAnything: false),
    ]

    static func rootURL(_ r: Root, home: URL) -> URL {
        home.appendingPathComponent("Library").appendingPathComponent(r.sub)
    }

    // MARK: names

    private static let tlds: Set<String> = ["com", "org", "net", "io", "co", "app", "dev", "me", "us", "uk", "de", "fr", "nl", "se", "ch", "ru", "ua",
                                            "jp", "cn", "kr", "tv", "ai", "eu", "ca", "au", "in", "it", "es", "pl", "cz", "sk", "info", "biz", "edu", "gov"]
    /// Apple's own, and parts of macOS that are not named com.apple.*
    private static let appleManaged: Set<String> = ["apple", "cloudkit", "familycircle", "geoservices", "metadata", "appleinternal"]

    /// "P8DQRXPVLP.com.eset.dunx" -> "com.eset.dunx", "group.com.x.y" -> "com.x.y", "a.b.plist" -> "a.b".
    /// Returns nil unless what is left is a reverse-DNS identifier that starts with a country or type prefix ("com.", "org.", "net.", ...).
    /// A plain name ("Google"), a file name ("default.store", "fsck_hfs.log") or a team-prefixed name that is not reverse-DNS ("UBF8T346G9.Office")
    /// says nothing reliable about who owns it, so it is never treated as a leftover.
    static func baseIdentifier(_ name: String) -> String? {
        var s = name
        for suffix in [".plist", ".savedState", ".binarycookies", ".lockfile"] where s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)); break }
        if let dot = s.firstIndex(of: "."), s.distance(from: s.startIndex, to: dot) == 10,
           s[s.startIndex..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) { s = String(s[s.index(after: dot)...]) }     // team ID prefix
        if s.hasPrefix("group.") { s = String(s.dropFirst(6)) }
        guard s.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+$"#, options: .regularExpression) != nil,
              let first = s.lowercased().split(separator: ".").first, tlds.contains(String(first)) else { return nil }
        return s
    }

    /// Who made it: the part after the country or type prefix ("com.eset.agent" -> "eset"), or the first part ("eset.shareddefaults" -> "eset").
    static func vendorToken(_ id: String) -> String {
        let parts = id.lowercased().split(separator: ".").map(String.init)
        guard let first = parts.first else { return "" }
        return tlds.contains(first) && parts.count > 1 ? parts[1] : first
    }

    // MARK: what is installed and what is running

    private static func bundleID(atApp appPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: appPath + "/Contents/Info.plist"),
              let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return d["CFBundleIdentifier"] as? String
    }

    /// Apps in the usual places (two levels deep, for folders such as Utilities), plus the helpers and extensions inside each.
    static func installedBundleIDs(home: URL) -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()
        func visit(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names where !n.hasPrefix(".") {
                let p = dir + "/" + n
                if n.hasSuffix(".app") {
                    if let id = bundleID(atApp: p) { ids.insert(id.lowercased()) }
                    for inner in ["Contents/Library/LoginItems", "Contents/PlugIns", "Contents/XPCServices", "Contents/Library/SystemExtensions"] {
                        for h in (try? fm.contentsOfDirectory(atPath: p + "/" + inner)) ?? [] {
                            if let id = bundleID(atApp: p + "/" + inner + "/" + h) { ids.insert(id.lowercased()) }
                        }
                    }
                } else if depth > 0 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { visit(p, depth: depth - 1) }
                }
            }
        }
        for d in ["/Applications", "/System/Applications", home.path + "/Applications"] { visit(d, depth: 2) }
        return ids
    }

    /// Bundle identifiers and path names of everything running (read with libproc, so no AppKit and no subprocess).
    static func runningSets() -> (ids: Set<String>, words: Set<String>) {
        var ids = Set<String>(), words = Set<String>()
        var seenApps = Set<String>()
        for pid in ProcTable.pids() {
            let path = ProcTable.path(pid)
            guard !path.isEmpty else { continue }
            let parts = path.split(separator: "/").map(String.init)
            for c in parts { words.insert(c.lowercased().replacingOccurrences(of: ".app", with: "")) }
            // the outermost .app of the path, and every .app inside it (helpers), identifies the app
            var prefix = ""
            for c in parts {
                prefix += "/" + c
                if c.hasSuffix(".app"), seenApps.insert(prefix).inserted, let id = bundleID(atApp: prefix) { ids.insert(id.lowercased()) }
            }
        }
        return (ids, words)
    }

    static func currentContext(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> StorageContext {
        let installed = installedBundleIDs(home: home)
        let running = runningSets()
        var ctx = StorageContext(home: home,
                                 installedTokens: Set(installed.map { vendorToken($0) }),
                                 installedIDs: installed, runningIDs: running.ids, runningWords: running.words)
        ctx.appExists = { id in !id.isEmpty && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
        return ctx
    }

    // MARK: classification (one place, used by the scan and again when you move something)

    struct Verdict {
        let kind: StorageKind
        let note: String
        let noteArg: String?
        let lock: String?
    }

    static let noteCache = trkey("Cache of an app. Apps rebuild it, so the first start afterwards can be a little slower.")
    static let noteLog = trkey("Log files of an app. Apps write new ones when they need them.")
    static let noteDeveloper = trkey("Xcode build files. Xcode makes them again the next time you build.")
    static let noteLeftover = trkey("No app from “%@” is installed or running. Make sure you no longer use it.")
    static let lockRunning = trkey("Used by a running app: quit it first.")

    /// nil means: never offered and never moved (macOS, this app, hidden files, names that say nothing).
    static func classify(name: String, root: Root, ctx: StorageContext) -> Verdict? {
        let lower = name.lowercased()
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        if lower.hasPrefix("com.apple.") || lower.contains(".com.apple.") || appleManaged.contains(lower) { return nil }     // also "group.com.apple.x", "243LU875E5.groups.com.apple.x"
        if lower.contains("bgoptimizer") || lower.contains(ctx.ownID.lowercased()) { return nil }          // this app's own files

        // Does it belong to an app that is gone?
        if let id = baseIdentifier(name) {
            let token = vendorToken(id)
            let appleToken = token == "apple"
            let known = ctx.installedTokens.contains(token) || ctx.installedIDs.contains(id.lowercased()) || ctx.appExists(id)
            if !appleToken, !known {
                let busy = ctx.runningWords.contains(token) || ctx.runningIDs.contains { vendorToken($0) == token }
                return Verdict(kind: .leftover, note: noteLeftover, noteArg: token, lock: busy ? lockRunning : nil)
            }
        }
        guard root.listsAnything else { return nil }          // from the other folders only leftovers are listed

        // A cache or log of an app that is still there. Never one of an installed security tool: those are not ours to touch.
        if Policy.isSecurityTool(name) { return nil }
        let running = ctx.runningIDs.contains { $0 == lower || $0.hasPrefix(lower + ".") || lower.hasPrefix($0 + ".") } || ctx.runningWords.contains(lower)
        let lock = running ? lockRunning : nil
        switch root.kind {
        case .cache: return Verdict(kind: .cache, note: noteCache, noteArg: nil, lock: lock)
        case .log: return Verdict(kind: .log, note: noteLog, noteArg: nil, lock: lock)
        case .developer: return Verdict(kind: .developer, note: noteDeveloper, noteArg: nil, lock: lock)
        case .leftover: return nil
        }
    }

    // MARK: sizes

    /// Total size on disk of a file or folder. Symbolic links are counted as links, never followed. Stops after `cap` entries.
    static func size(of url: URL, cap: Int = 200_000) -> (bytes: Int64, approximate: Bool) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        func own(_ u: URL) -> Int64 { Int64((try? u.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0) }
        var total = own(url)
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return (total, false) }
        var n = 0
        for case let u as URL in e {
            total += own(u)
            n += 1
            if n >= cap { return (total, true) }
        }
        return (total, false)
    }

    static func isSymlink(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    // MARK: the scan

    static func scan(ctx: StorageContext) -> [StorageItem] {
        let fm = FileManager.default
        var items: [StorageItem] = []
        var seen = Set<String>()
        for root in roots {
            let dir = rootURL(root, home: ctx.home)
            guard !isSymlink(dir.path), let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names.sorted() {
                let path = dir.appendingPathComponent(name).path
                guard !isSymlink(path), let v = classify(name: name, root: root, ctx: ctx), seen.insert(path).inserted else { continue }
                items.append(StorageItem(name: name, path: path, kind: v.kind, bytes: nil, approximate: false, note: v.note, noteArg: v.noteArg, lock: v.lock))
            }
        }
        // sizes in parallel; folders macOS keeps closed are not read at all
        let listed = items
        var sizes = [(Int64, Bool)?](repeating: nil, count: listed.count)
        let readable = listed.map { it in roots.first { r in it.path.hasPrefix(rootURL(r, home: ctx.home).path + "/") }?.sizeReadable ?? false }
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: listed.count) { i in
            guard readable[i] else { return }
            let s = size(of: URL(fileURLWithPath: listed[i].path))
            lock.lock(); sizes[i] = s; lock.unlock()
        }
        for i in items.indices { if let s = sizes[i] { items[i].bytes = s.0; items[i].approximate = s.1 } }
        return items.sorted { ($0.sortBytes, $1.name) > ($1.sortBytes, $0.name) }
    }
}

// MARK: - the one change

enum StorageAction {
    /// Move one item to the Trash. Throws, and changes nothing, if any rule is not met. `trash` is replaceable for tests.
    @discardableResult
    static func moveToTrash(path: String, observeOnly: Bool, ctx: StorageContext,
                            trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> Int64? {
        let no = StorageError.notAllowed(trkey("That item cannot be moved here."))
        // 1. never while the app is only observing
        if observeOnly { throw StorageError.notAllowed(trkey("Turn off Observe only to change files")) }
        // 2. an absolute path with no tricks, directly inside one of the listed folders of YOUR Library (symbolic links resolved first)
        let url = URL(fileURLWithPath: path)
        guard path.hasPrefix("/"), url.standardizedFileURL.path == path, !path.contains("/../") else { throw no }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard let root = StorageScanner.roots.first(where: { StorageScanner.rootURL($0, home: ctx.home).resolvingSymlinksInPath().path == parent }),
              !StorageScanner.isSymlink(StorageScanner.rootURL(root, home: ctx.home).path) else { throw no }
        // 3. the item itself is a real file or folder, not a link, and is still there
        guard !StorageScanner.isSymlink(path), FileManager.default.fileExists(atPath: path) else { throw no }
        // 4. it is still something we would offer, and nothing running is using it
        guard let v = StorageScanner.classify(name: url.lastPathComponent, root: root, ctx: ctx) else { throw no }
        if let why = v.lock { throw StorageError.notAllowed(why) }
        let bytes = root.sizeReadable ? StorageScanner.size(of: url).bytes : nil
        // 5. the Trash does the work: the item can be put back
        do { try trash(url) } catch { throw StorageError.failed(trkey("macOS did not allow it. Try it in Finder.")) }
        return bytes
    }
}
