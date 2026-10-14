// Storage tab: how names are read, what counts as a leftover, what is never offered, the rules for Move to Trash, and a real read of this Mac.
// Everything that changes anything happens in a temporary folder that stands in for the home folder. The Trash is replaced by a
// recording stand-in, except for one check that moves a file made by this test to the real Trash and removes it from there again.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }

// ---- reading names
check(StorageScanner.baseIdentifier("com.malwarebytes.mbam.frontend.agent.plist") == "com.malwarebytes.mbam.frontend.agent", "name: .plist removed")
check(StorageScanner.baseIdentifier("P8DQRXPVLP.com.eset.dunx") == "com.eset.dunx", "name: team ID prefix removed")
check(StorageScanner.baseIdentifier("group.com.example.shared") == "com.example.shared", "name: group. prefix removed")
check(StorageScanner.baseIdentifier("com.eset.ecs.onboarding.savedState") == "com.eset.ecs.onboarding", "name: .savedState removed")
check(StorageScanner.baseIdentifier("eset.shareddefaultssuite.plist") == nil, "name: without a com./org./net. prefix it is not trusted")
check(StorageScanner.baseIdentifier("default.store") == nil && StorageScanner.baseIdentifier("fsck_hfs.log") == nil && StorageScanner.baseIdentifier("AtlasUpdateHelper.log") == nil, "name: file names are not identifiers")
check(StorageScanner.baseIdentifier("UBF8T346G9.Office.Excel.WidgetExtension") == nil && StorageScanner.baseIdentifier("group.is.workflow.shortcuts") == nil, "name: team-prefixed or group names that are not reverse-DNS are not trusted")
check(StorageScanner.baseIdentifier("Google") == nil && StorageScanner.baseIdentifier("Mac Monitor") == nil, "name: a plain name says nothing about who owns it")
check(StorageScanner.baseIdentifier("loginwindow") == nil && StorageScanner.baseIdentifier("a b.c") == nil, "name: spaces and no dots are not identifiers")
check(StorageScanner.vendorToken("com.eset.agent.finderextension") == "eset", "vendor: com.eset.x is eset")
check(StorageScanner.vendorToken("eset.shareddefaultssuite") == "eset", "vendor: eset.x is eset")
check(StorageScanner.vendorToken("ru.keepcoder.Telegram") == "keepcoder", "vendor: other country prefixes")

// ---- a stand-in home folder
let fm = FileManager.default
let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("bgopt-storage-\(UUID().uuidString)")
let home = URL(fileURLWithPath: tmp).resolvingSymlinksInPath()
let lib = home.appendingPathComponent("Library")
func make(_ rel: String, bytes: Int = 4096, dir: Bool = true) {
    let u = lib.appendingPathComponent(rel)
    if dir { try! fm.createDirectory(at: u, withIntermediateDirectories: true); try! Data(count: bytes).write(to: u.appendingPathComponent("data.bin")) }
    else { try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try! Data(count: bytes).write(to: u) }
}
make("Caches/com.google.Chrome", bytes: 50_000)
make("Caches/com.microsoft.wdav")                      // an installed security tool's cache
make("Caches/com.apple.Safari")
make("Caches/CloudKit")
make("Caches/.hidden")
make("Caches/BGOptimizer")
make("Caches/com.eset.cache.old", bytes: 8000)          // cache of a removed app
make("Caches/Homebrew", bytes: 30_000)
make("Logs/DiagnosticReports")
make("Logs/Zoom", bytes: 9000)
make("Developer/Xcode/DerivedData/MyApp-abc", bytes: 70_000)
make("Preferences/com.malwarebytes.mbam.frontend.agent.plist", bytes: 600, dir: false)
make("Preferences/com.google.Chrome.plist", bytes: 600, dir: false)
make("Preferences/com.apple.finder.plist", bytes: 600, dir: false)
make("Preferences/loginwindow.plist", bytes: 600, dir: false)
make("Preferences/eset.shareddefaultssuite.plist", bytes: 600, dir: false)
make("Group Containers/243LU875E5.groups.com.apple.podcasts")
make("Group Containers/group.is.workflow.shortcuts")
make("Logs/AtlasUpdateHelper.log", dir: false)
make("Application Support/com.malwarebytes.mbam")
make("Application Support/Mac Monitor")                // a plain name: cannot be tied to anyone
make("Application Support/Google")
make("Saved Application State/com.eset.ecs.onboarding.savedState")
make("Containers/com.eset.agent.finderextension")
make("Group Containers/P8DQRXPVLP.com.eset.dunx")
make("Group Containers/UBF8T346G9.Office")              // no identifier left after the team prefix
make("Containers/com.google.Chrome.helper")             // an installed vendor
make("Caches/weird\nname")
make("Caches/com.evil.\u{202E}gpj.exe")                 // right-to-left override
make("Caches/com.evil.zero\u{200B}width")                // zero-width space
make("Caches/com.evil.line\u{2028}break")               // line separator                              // a control character in the name
try! fm.createSymbolicLink(atPath: lib.appendingPathComponent("Caches/linkedcache").path, withDestinationPath: "/etc")
try! fm.createSymbolicLink(atPath: lib.appendingPathComponent("Preferences/com.link.leftover.plist").path, withDestinationPath: "/etc/hosts")

func context(running: Set<String> = [], words: Set<String> = []) -> StorageContext {
    StorageContext(home: home, installedTokens: ["google", "microsoft"], installedIDs: ["com.google.chrome", "com.microsoft.wdav"],
                   runningIDs: running, runningWords: words, appExists: { _ in false }, ownID: "com.alexxxela.bgoptimizer")
}
let ctx = context()

// ---- the scan
let items = StorageScanner.scan(ctx: ctx)
func item(_ rel: String) -> StorageItem? { items.first { $0.path == lib.appendingPathComponent(rel).path } }
func kind(_ rel: String) -> StorageKind? { item(rel)?.kind }
check(kind("Caches/com.google.Chrome") == .cache, "scan: an installed app's cache is a cache")
check(kind("Caches/Homebrew") == .cache && kind("Logs/Zoom") == .log, "scan: caches and logs are listed")
check(kind("Developer/Xcode/DerivedData/MyApp-abc") == .developer, "scan: Xcode build files are listed")
check(kind("Caches/com.eset.cache.old") == .leftover, "scan: a cache of a removed app is a possible leftover")
check(kind("Preferences/com.malwarebytes.mbam.frontend.agent.plist") == .leftover, "scan: preferences of a removed app are a possible leftover")
check(kind("Application Support/com.malwarebytes.mbam") == .leftover && kind("Saved Application State/com.eset.ecs.onboarding.savedState") == .leftover, "scan: Application Support and saved state of removed apps")
check(kind("Containers/com.eset.agent.finderextension") == .leftover && kind("Group Containers/P8DQRXPVLP.com.eset.dunx") == .leftover, "scan: containers of removed apps")
check(item("Containers/com.eset.agent.finderextension")?.bytes == nil, "scan: a container's size is not read")
check(item("Caches/com.eset.cache.old")?.bytes ?? 0 >= 8000, "scan: sizes are read for the others")
check(item("Caches/com.microsoft.wdav") == nil, "scan: an installed security tool's cache is not offered")
for never in ["Caches/com.apple.Safari", "Caches/CloudKit", "Caches/.hidden", "Caches/BGOptimizer", "Preferences/com.apple.finder.plist", "Preferences/loginwindow.plist",
              "Application Support/Mac Monitor", "Application Support/Google", "Group Containers/UBF8T346G9.Office", "Preferences/com.google.Chrome.plist",
              "Containers/com.google.Chrome.helper", "Preferences/eset.shareddefaultssuite.plist", "Group Containers/243LU875E5.groups.com.apple.podcasts", "Group Containers/group.is.workflow.shortcuts", "Caches/linkedcache", "Preferences/com.link.leftover.plist"] {
    check(item(never) == nil, "scan: never offered: \(never)")
}
check(!items.contains { $0.name.contains("\n") }, "scan: a name with a control character is never offered")
check(!items.contains { plainText($0.name) != $0.name }, "scan: no name with invisible or direction-changing characters is offered")
check(move(p("Caches/com.evil.\u{202E}gpj.exe")).hasPrefix("refused") && move(p("Caches/com.evil.zero\u{200B}width")).hasPrefix("refused"), "refused: a name with a right-to-left override or a zero-width character")
check(plainText("a\u{202E}b\u{200B}c\u{2028}d\ne\u{7F}f") == "a b c d e f" && plainText("Zoom Привіт") == "Zoom Привіт", "plainText: hides nothing readable, replaces only the invisible and control characters")
check(zip(items, items.dropFirst()).allSatisfy { $0.sortBytes >= $1.sortBytes }, "scan: sorted biggest first")
check(items.allSatisfy { $0.lock == nil }, "scan: nothing is running, so nothing is locked")

// ---- running apps lock what they use
let busy = StorageScanner.scan(ctx: context(running: ["com.google.chrome"], words: ["eset", "zoom"]))
func lockOf(_ rel: String) -> String? { busy.first { $0.path == lib.appendingPathComponent(rel).path }?.lock }
check(lockOf("Caches/com.google.Chrome") != nil, "running: the cache of a running app is locked")
check(lockOf("Logs/Zoom") != nil, "running: a log named like a running program is locked")
check(lockOf("Preferences/com.malwarebytes.mbam.frontend.agent.plist") == nil, "running: an unrelated leftover is not locked")
check(lockOf("Caches/com.eset.cache.old") != nil && lockOf("Group Containers/P8DQRXPVLP.com.eset.dunx") != nil, "running: a leftover whose vendor name is running is locked")

// ---- Move to Trash: the rules
var trashed: [String] = []
let fake: (URL) throws -> Void = { trashed.append($0.path) }
func move(_ path: String, observe: Bool = false, c: StorageContext = ctx) -> String {
    trashed = []
    do { _ = try StorageAction.moveToTrash(path: path, observeOnly: observe, ctx: c, trash: fake); return trashed.isEmpty ? "NOTHING" : "OK" }
    catch let e as StorageError { switch e { case .notAllowed(let k): return "refused: \(k)"; case .failed(let k): return "failed: \(k)" } }
    catch { return "error" }
}
func p(_ rel: String) -> String { lib.appendingPathComponent(rel).path }
check(move(p("Caches/Homebrew")) == "OK" && trashed == [p("Caches/Homebrew")], "move: a cache goes to the Trash")
check(move(p("Preferences/com.malwarebytes.mbam.frontend.agent.plist")) == "OK", "move: a leftover preference file goes to the Trash")
check(move(p("Containers/com.eset.agent.finderextension")) == "OK", "move: a container of a removed app is accepted (macOS may still refuse)")
check(move(p("Caches/Homebrew"), observe: true).hasPrefix("refused"), "refused: while Observe only is on")
check(trashed.isEmpty, "  ... and nothing was moved")
check(move(p("Caches/com.apple.Safari")).hasPrefix("refused"), "refused: a com.apple. item")
check(move(p("Caches/CloudKit")).hasPrefix("refused"), "refused: macOS-managed folder")
check(move(p("Caches/BGOptimizer")).hasPrefix("refused"), "refused: this app's own folder")
check(move(p("Caches/com.microsoft.wdav")).hasPrefix("refused"), "refused: an installed security tool")
check(move(p("Caches/linkedcache")).hasPrefix("refused"), "refused: a symbolic link")
check(move(p("Preferences/com.link.leftover.plist")).hasPrefix("refused"), "refused: a symbolic link to a file")
check(move(p("Caches")).hasPrefix("refused"), "refused: the folder itself")
check(move(lib.path).hasPrefix("refused") && move(home.path).hasPrefix("refused") && move("/").hasPrefix("refused"), "refused: Library, home and the root")
check(move(p("Caches/Homebrew/data.bin")).hasPrefix("refused"), "refused: something inside an item (only whole items move)")
check(move(p("Caches/../Preferences/com.malwarebytes.mbam.frontend.agent.plist")).hasPrefix("refused"), "refused: path tricks (..)")
check(move("Caches/Homebrew").hasPrefix("refused"), "refused: a relative path")
check(move("/etc/hosts").hasPrefix("refused") && move("/Library/Caches/com.example").hasPrefix("refused") && move("/Applications/Safari.app").hasPrefix("refused"), "refused: outside your own Library")
check(move(p("Caches/does-not-exist")).hasPrefix("refused"), "refused: it is not there")
check(move(p("Application Support/Google")).hasPrefix("refused") && move(p("Preferences/com.google.Chrome.plist")).hasPrefix("refused"), "refused: something of an installed app in a leftover-only folder")
check(move(p("Caches/com.google.Chrome"), c: context(running: ["com.google.chrome"])).hasPrefix("refused"), "refused: the cache of a running app")
check(move(p("Caches/com.eset.cache.old"), c: context(words: ["eset"])).hasPrefix("refused"), "refused: a leftover whose vendor is running now")
let failing: (URL) throws -> Void = { _ in throw CocoaError(.fileWriteNoPermission) }
do { _ = try StorageAction.moveToTrash(path: p("Caches/Homebrew"), observeOnly: false, ctx: ctx, trash: failing); check(false, "a Trash failure should be reported") }
catch let e as StorageError { if case .failed = e { check(true, "failed: when macOS refuses, the error says so") } else { check(false, "wrong error kind") } } catch { check(false, "wrong error") }
check(fm.fileExists(atPath: p("Caches/Homebrew")), "nothing was deleted by the stand-in Trash")
// a symbolic link in place of a root folder
let hijackHome = URL(fileURLWithPath: tmp + "-hijack").resolvingSymlinksInPath()
try! fm.createDirectory(at: hijackHome.appendingPathComponent("Library"), withIntermediateDirectories: true)
try! fm.createDirectory(atPath: tmp + "-elsewhere/victim", withIntermediateDirectories: true)
try! fm.createSymbolicLink(atPath: hijackHome.appendingPathComponent("Library/Caches").path, withDestinationPath: tmp + "-elsewhere")
var hctx = ctx; hctx.home = hijackHome
check(move(hijackHome.path + "/Library/Caches/victim", c: hctx).hasPrefix("refused"), "refused: a root folder that is a link to somewhere else")
check(StorageScanner.scan(ctx: hctx).isEmpty, "scan: a root folder that is a link is not read")

// ---- one real move to the real Trash, of a file this test made
let probe = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bgopt-trash-probe-\(UUID().uuidString).txt")
try! Data("probe".utf8).write(to: probe)
var result: NSURL?
do {
    try fm.trashItem(at: probe, resultingItemURL: &result)
    check(!fm.fileExists(atPath: probe.path) && result.map { fm.fileExists(atPath: $0.path ?? "") } == true, "real Trash: the file left its place and is in the Trash")
    if let r = result as URL? { try? fm.removeItem(at: r) }     // remove only the file this test made
} catch { print("  skipped: this machine has no usable Trash (\(error.localizedDescription))") }

// ---- this Mac, read for real (read only)
let real = StorageScanner.currentContext()
check(!real.installedIDs.isEmpty && real.installedTokens.contains("apple"), "real: installed apps found (at least the ones macOS ships)")
check(!real.runningWords.isEmpty, "real: running programs found")
let realItems = StorageScanner.scan(ctx: real)
print("  (this Mac: \(realItems.count) items; \(realItems.filter { $0.kind == .leftover }.count) possible leftovers)")
let realLib = real.home.appendingPathComponent("Library").path
check(realItems.allSatisfy { $0.path.hasPrefix(realLib + "/") }, "real: every item is inside your own Library")
check(!realItems.contains { $0.name.lowercased().hasPrefix("com.apple.") }, "real: no com.apple. item")
check(!realItems.contains { $0.name.lowercased().contains("bgoptimizer") }, "real: nothing of this app")
check(realItems.allSatisfy { !StorageScanner.isSymlink($0.path) }, "real: no symbolic link")
check(realItems.allSatisfy { i in !(i.kind != .leftover && Policy.isSecurityTool(i.name)) }, "real: no installed security tool's cache or log")

try? fm.removeItem(atPath: tmp); try? fm.removeItem(atPath: tmp + "-hijack"); try? fm.removeItem(atPath: tmp + "-elsewhere")
print(failures == 0 ? "STORAGE: ALL PASSED" : "STORAGE: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
