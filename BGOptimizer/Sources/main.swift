import AppKit
import Combine
import ServiceManagement
import SwiftUI

var signalSources: [DispatchSourceSignal] = []

/// Give everything back before the process dies, whatever kills it.
func installSignalHandlers(_ engine: Engine) {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { engine.shutdownSync(); exit(0) }
        s.resume()
        signalSources.append(s)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { handler() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private let log = ActionLog()
    private let model = AppModel()
    private var engine: Engine!
    private var window: NSWindow?
    private let activity = ActivityModel()
    private var activityWindow: NSWindow?
    private let firstRunDraft = FirstRunDraft()
    private var firstRunWindow: NSWindow?
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil); return            // one copy only
        }
        L10n.apply(model.settings.language)
        activity.language = L10n.code
        installMainMenu()
        engine = Engine(model.settings.config, log)
        engine.recoverFromCrash()
        engine.update(model.settings.config, protectedApps: model.settings.protectedApps)
        engine.onChange = { [weak self] list in self?.model.slowed = list }
        engine.onActivity = { [weak self] rows, total in
            self?.activity.rows = rows
            self?.activity.ownCount = total
            self?.activity.updated = Date()
        }
        activity.logProvider = { [weak self] in self?.log.tail(200) ?? "" }
        engine.onNotice = { [weak self] text, isError in self?.activity.showNotice(text, error: isError) }
        model.onEnabled = { [weak self] on in
            guard let self = self else { return }
            if on { self.engine.start() } else { self.engine.stop(); self.model.slowed = [] }
        }
        model.onSettings = { [weak self] s in
            if L10n.resolve(s.language) != L10n.code { self?.applyLanguage(s.language) }
            self?.engine.update(s.config, protectedApps: s.protectedApps)
            if s.observeOnly { self?.engine.releaseAll() }       // observing means changing nothing
        }
        installSignalHandlers(engine)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let actions = PanelActions(
            restore: { [weak self] in self?.engine.release($0) },
            giveBack: { [weak self] in self?.engine.releaseAll() },
            openSettings: { [weak self] in self?.popover.performClose(nil); self?.showSettings() },
            openActivity: { [weak self] in self?.popover.performClose(nil); self?.showActivity() },
            quit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: PanelView(model: model, actions: actions))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        Publishers.CombineLatest(model.$enabled, model.$slowed).receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshIcon() }.store(in: &bag)
        Publishers.CombineLatest(model.$enabled, model.$settings).receive(on: RunLoop.main)
            .sink { [weak self] on, settings in
                self?.activity.engineOn = on
                self?.activity.observeOnly = settings.observeOnly
            }.store(in: &bag)
        refreshLogin()
        if model.enabled { engine.start() }
        if CommandLine.arguments.contains("--open-settings") { showSettings() }
        if CommandLine.arguments.contains("--open-activity") { showActivity() }
        if CommandLine.arguments.contains("--selftest-window") { runWindowSelfTest() }
        if CommandLine.arguments.contains("--open-activity-minimized") {       // dev aid for measuring the cost of a minimized window
            showActivity()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.activityWindow?.miniaturize(nil) }
        }
        let firstTime = !UserDefaults.standard.bool(forKey: "didOnboard") && UserDefaults.standard.object(forKey: enabledKey) == nil
        if firstTime || CommandLine.arguments.contains("--first-run") { showFirstRun() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshotSettings(to: CommandLine.arguments[i + 1])
        }
    }

    /// Dev aid: draw the Settings window to a PNG (needs no screen-recording permission) and quit.
    private func snapshotSettings(to path: String) {
        showSettings()
        guard let w = window, let view = w.contentView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ note: Notification) { engine.shutdownSync() }

    private func refreshIcon() {
        let img = NSImage(systemSymbolName: model.enabled ? "speedometer" : "pause.circle", accessibilityDescription: "BG Optimizer")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.title = img == nil ? "BG" : (model.slowed.isEmpty ? "" : " \(model.slowed.count)")
        let n = model.slowed.count
        item.button?.setAccessibilityLabel("BG Optimizer")
        item.button?.setAccessibilityValue(!model.enabled ? tr("off") : (model.settings.observeOnly ? tr("observing only")
            : (n == 0 ? tr("on, nothing slowed") : trPlural("on, jobs slowed", n))))
    }

    /// Left click: the panel. Right click or control click: the plain menu (also a way in if the icon is crowded out).
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            item.menu = menu
            item.button?.performClick(nil)
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            model.objectWillChange.send()                 // refresh "slowed 4 minutes ago"
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func menuDidClose(_ menu: NSMenu) { item.menu = nil }

    /// Switch a startup item of yours on or off for the next login. The checks are made again inside StartupControlAction.
    private func setStartup(_ item: StartupItem, _ on: Bool) {
        guard let path = item.plistPath else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try StartupControlAction.setEnabled(label: item.label, plistPath: path, enable: on)
                self?.log.write("STARTUP", "\(item.label) \(on ? "switched on" : "switched off") by you (applies at the next login)")
                DispatchQueue.main.async {
                    self?.activity.setStartupEnabled(item.id, on)
                    self?.activity.showNotice(on ? tr("“%@” will start at the next login again.", item.name)
                                                 : tr("“%@” will not start at the next login. What is running now keeps running.", item.name), error: false)
                    self?.activity.refreshStartup()
                }
            } catch {
                var key = "macOS did not accept the change."
                if let e = error as? StartupError { switch e { case .notAllowed(let k), .failed(let k): key = k } }
                self?.log.write("REFUSED", "startup \(item.label): \(key)")
                DispatchQueue.main.async {
                    self?.activity.showNotice(tr("Could not change “%@”: %@", item.name, tr(key)), error: true)
                    self?.activity.refreshStartup()          // puts the switch back to the real state
                }
            }
        }
    }

    /// Move one Storage item to the Trash. The checks are made again inside StorageAction, with a fresh look at what is running.
    private func trashStorage(_ item: StorageItem) {
        let observeOnly = model.settings.observeOnly
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let bytes = try StorageAction.moveToTrash(path: item.path, observeOnly: observeOnly, ctx: StorageScanner.currentContext())
                self?.log.write("STORAGE", "\(item.path) moved to the Trash by you (\(bytes.map { "\($0) bytes" } ?? "size not read"))")
                DispatchQueue.main.async {
                    self?.activity.storage.removeAll { $0.id == item.id }
                    self?.activity.showNotice(tr("Moved “%@” to the Trash.", item.name), error: false)
                    self?.activity.refreshStorage()
                }
            } catch {
                var key = "That item cannot be moved here."
                if let e = error as? StorageError { switch e { case .notAllowed(let k), .failed(let k): key = k } }
                self?.log.write("REFUSED", "storage \(item.path): \(key)")
                DispatchQueue.main.async {
                    self?.activity.showNotice(tr("Could not move “%@”: %@", item.name, tr(key)), error: true)
                    self?.activity.refreshStorage()
                }
            }
        }
    }

    /// The menu of a row's "…" button, opened at the mouse.
    private func showRowMenu(_ row: ActivityRow) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in rowMenuEntries(row) {
            switch entry {
            case .separator: menu.addItem(.separator())
            case let .item(title, enabled, action):
                let item = ClosureMenuItem(title: title) { [weak self] in
                    guard let self = self else { return }
                    switch action {
                    case .restore: self.engine.release(row.pid)
                    case .slow: self.engine.slowManually(pid: row.pid, start: row.start, confirmedInteractive: false)
                    case .askToSlow: self.activity.pending = row
                    case .protect(let name): self.protectApp(name)
                    case .unprotect(let name): self.unprotectApp(name)
                    case .none: break
                    }
                }
                item.isEnabled = enabled
                menu.addItem(item)
            }
        }
        // Open to the left of the button, so the menu stays over the window instead of hanging off its right edge.
        let mouse = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: mouse.x - menu.size.width + 22, y: mouse.y + 2), in: nil)
    }

    /// "Never slow this app": adds it to your protected list (Settings > Protected apps). The engine releases it if it was slowed.
    private func protectApp(_ name: String) {
        var s = model.settings
        guard !name.isEmpty, !s.protectedApps.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        s.protectedApps.append(name)
        model.settings = s
        log.write("PROTECT", "\(name) added to the protected list")
        activity.showNotice(tr("“%@” will never be slowed.", name), error: false)
    }

    private func unprotectApp(_ name: String) {
        var s = model.settings
        s.protectedApps.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        model.settings = s
        log.write("PROTECT", "\(name) removed from the protected list")
        activity.showNotice(tr("“%@” removed from the protected list.", name), error: false)
    }

    /// Switch the language live: the SwiftUI windows redraw themselves; titles, the menu-bar item and menu are updated here.
    private func applyLanguage(_ language: AppLanguage) {
        L10n.apply(language)
        activity.language = L10n.code
        activityWindow?.title = tr("Activity")
        firstRunWindow?.title = tr("Welcome to BG Optimizer")
        installMainMenu()
        refreshIcon()
    }

    private func refreshLogin() { model.loginEnabled = SMAppService.mainApp.status == .enabled }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLogin()
        menu.removeAllItems()
        let head = NSMenuItem(title: model.enabled ? tr("BG Optimizer is on") : tr("BG Optimizer is off"), action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)

        let toggle = NSMenuItem(title: tr("Optimize background jobs"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        if model.enabled {
            let line = NSMenuItem(title: model.slowed.isEmpty ? tr("Nothing slowed down") : tr("Slowed down (low priority):"), action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
            for s in model.slowed.prefix(8) {
                let row = NSMenuItem(title: "   \(s.name)", action: nil, keyEquivalent: "")
                row.isEnabled = false
                menu.addItem(row)
            }
            if !model.slowed.isEmpty {
                let give = NSMenuItem(title: tr("Give everything back now"), action: #selector(giveBack), keyEquivalent: "")
                give.target = self
                menu.addItem(give)
            }
            menu.addItem(.separator())
        }

        let activityItem = NSMenuItem(title: tr("Activity…"), action: #selector(showActivity), keyEquivalent: "y")
        activityItem.target = self
        menu.addItem(activityItem)
        let settings = NSMenuItem(title: tr("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: tr("Launch at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = model.loginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("Quit BG Optimizer"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleEnabled() { model.enabled.toggle() }
    @objc private func giveBack() { engine.releaseAll() }
    @objc private func toggleLogin() { setLogin(SMAppService.mainApp.status != .enabled) }

    private func setLogin(_ on: Bool) {
        let svc = SMAppService.mainApp
        guard on != (svc.status == .enabled) else { return }
        do {
            log.write("LOGIN", "launch at login \(on ? "on" : "off") (changed in the app)")
            if on { try svc.register() } else { try svc.unregister() }
        } catch {
            let a = NSAlert()
            a.messageText = tr("Could not change Launch at login")
            a.informativeText = "\(error.localizedDescription)\n\n" + tr("Tip: run the app from ~/Applications (see README).")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refreshLogin()
    }

    @objc private func showActivity() {
        if activityWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = tr("Activity")
            let actions = ActivityActions(
                slow: { [weak self] row, confirmed in self?.engine.slowManually(pid: row.pid, start: row.start, confirmedInteractive: confirmed) },
                restore: { [weak self] pid in self?.engine.release(pid) },
                protect: { [weak self] name in self?.protectApp(name) },
                unprotect: { [weak self] name in self?.unprotectApp(name) },
                clearLog: { [weak self] in
                    self?.log.clear()
                    self?.activity.logText = ""
                    self?.activity.showNotice(tr("Log cleared."), error: false)
                },
                showMenu: { [weak self] row in self?.showRowMenu(row) },
                setStartup: { [weak self] item, on in self?.setStartup(item, on) },
                openLoginSettings: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!) },
                trashStorage: { [weak self] item in self?.trashStorage(item) },
                revealStorage: { item in
                    let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
                    if item.path.hasPrefix(home + "/") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                })
            w.contentView = NSHostingView(rootView: ActivityView(model: activity, actions: actions))
            w.contentMinSize = NSSize(width: 600, height: 440)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            activityWindow = w
        }
        resumeActivity()
        showDockPresence()
        activityWindow?.makeKeyAndOrderFront(nil)
    }

    private func showFirstRun() {
        if firstRunWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = tr("Welcome to BG Optimizer")
            w.contentView = NSHostingView(rootView: FirstRunView(draft: firstRunDraft, model: model, onStart: { [weak self] in self?.finishFirstRun() }))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            firstRunWindow = w
        }
        showDockPresence()
        firstRunWindow?.makeKeyAndOrderFront(nil)
    }

    /// Applies the welcome choices. Closing the window without choosing leaves everything off and does not ask again.
    private func finishFirstRun() {
        var s = model.settings
        s.observeOnly = firstRunDraft.observeOnly
        model.settings = s
        model.enabled = true
        if firstRunDraft.openAtLogin { setLogin(true) }
        log.write("WELCOME", "started in \(s.observeOnly ? "observe-only" : "optimizing") mode")
        firstRunWindow?.close()
    }

    /// Dev aid: opens the Activity window, minimizes it, restores it and closes it, writing what the app does at each step to the log.
    private func runWindowSelfTest() {
        func state(_ label: String) {
            let w = activityWindow
            let policy = NSApp.activationPolicy() == .regular ? "regular (Dock icon)" : "accessory (menu bar only)"
            log.write("SELFTEST", "\(label): \(policy), minimized=\(w?.isMiniaturized ?? false), visible=\(w?.isVisible ?? false), "
                      + "refreshTimer=\(activity.isRefreshing), engineBuildsRows=\(engine.activityEnabled), startupItems=\(activity.startup.count), storageItems=\(activity.storage.count), mainMenuTitles=\(NSApp.mainMenu?.items.map { $0.title } ?? [])")
        }
        func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
        at(0.5) { state("start (nothing open)") }
        at(1.0) { self.showActivity() }
        at(1.5) { self.activity.select(.startup) }                   // reads the real startup list (about 3 s)
        at(5.5) { state("Startup tab loaded") }
        at(5.6) { self.activity.select(.storage) }                   // reads your Library (read only)
        at(10.0) { state("Storage tab loaded") }
        at(10.1) { self.activityWindow?.miniaturize(nil) }
        at(12.5) { state("window minimized") }
        at(12.6) { self.activityWindow?.deminiaturize(nil) }
        at(15.0) { state("window restored") }
        at(15.1) { self.activityWindow?.close() }
        at(16.5) { state("window closed") }
        at(17.0) { NSApp.terminate(nil) }
    }

    // MARK: Dock icon, menu bar and window lifecycle

    /// While one of our windows is open (or minimized) the app behaves like a normal app: Dock icon, menu bar, ⌘-Tab,
    /// and the minimized window carries the app icon. With no window left it goes back to a menu-bar-only app.
    private func showDockPresence() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateDockPresence() {
        let open = [window, activityWindow, firstRunWindow].contains { $0.map { $0.isVisible || $0.isMiniaturized } ?? false }
        if !open, NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
    }

    /// The Activity window only works (samples, rows, timers) while it can be seen.
    private func resumeActivity() {
        activity.start()
        engine.setActivity(true)
    }

    private func pauseActivity() {
        activity.stop()
        engine.setActivity(false)
    }

    func windowDidMiniaturize(_ n: Notification) { if (n.object as? NSWindow) === activityWindow { pauseActivity() } }
    func windowDidDeminiaturize(_ n: Notification) { if (n.object as? NSWindow) === activityWindow { resumeActivity() } }

    /// Covered by other windows or on another Space: nothing to draw, so nothing to compute.
    func windowDidChangeOcclusionState(_ n: Notification) {
        guard let w = n.object as? NSWindow, w === activityWindow, !w.isMiniaturized else { return }
        if w.occlusionState.contains(.visible) { resumeActivity() } else { pauseActivity() }
    }

    func windowWillClose(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        if w === activityWindow {
            pauseActivity()
        } else if w === firstRunWindow {
            UserDefaults.standard.set(true, forKey: "didOnboard")
        }
        DispatchQueue.main.async { self.updateDockPresence() }
    }

    /// A real main menu. Without one, ⌘C ⌘V ⌘A do not work in the text fields, and ⌘W ⌘M ⌘Q do nothing.
    private func installMainMenu() {
        let name = "BG Optimizer"
        let main = NSMenu()
        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            menu.addItem(item)
        }
        func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
            let menu = NSMenu(title: title)
            build(menu)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            return item
        }
        main.addItem(submenu(name) { m in
            add(m, tr("About %@", name), #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
            m.addItem(.separator())
            add(m, tr("Settings…"), #selector(showSettings), ",", target: self)
            m.addItem(.separator())
            add(m, tr("Hide %@", name), #selector(NSApplication.hide(_:)), "h", target: NSApp)
            add(m, tr("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option], target: NSApp)
            add(m, tr("Show All"), #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
            m.addItem(.separator())
            add(m, tr("Quit %@", name), #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        })
        main.addItem(submenu(tr("Edit")) { m in
            add(m, tr("Undo"), Selector(("undo:")), "z")
            add(m, tr("Redo"), Selector(("redo:")), "z", mods: [.command, .shift])
            m.addItem(.separator())
            add(m, tr("Cut"), #selector(NSText.cut(_:)), "x")
            add(m, tr("Copy"), #selector(NSText.copy(_:)), "c")
            add(m, tr("Paste"), #selector(NSText.paste(_:)), "v")
            add(m, tr("Select All"), #selector(NSText.selectAll(_:)), "a")
        })
        main.addItem(submenu(tr("View")) { m in
            add(m, tr("Activity…"), #selector(showActivity), "y", target: self)
        })
        let windowItem = submenu(tr("Window")) { m in
            add(m, tr("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
            add(m, tr("Zoom"), #selector(NSWindow.performZoom(_:)))
            add(m, tr("Close"), #selector(NSWindow.performClose(_:)), "w")
            m.addItem(.separator())
            add(m, tr("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
        }
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowItem.submenu
    }

    @objc private func showSettings() {
        if window == nil {
            let actions = SettingsActions(
                setLogin: { [weak self] in self?.setLogin($0) },
                giveBack: { [weak self] in self?.engine.releaseAll() })
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "BG Optimizer"
            w.contentView = NSHostingView(rootView: SettingsView(model: model, actions: actions))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        refreshLogin()
        showDockPresence()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Dev aid: draw the panel in each state to PNG files (<prefix>-<state>.png), then exit. Starts no engine and touches no saved settings,
/// so it is safe to run while the real app is running.
func snapshotPanel(prefix: String) -> Never {
    let jobs = [Slowed(pid: 4182, start: 0, name: "HandBrakeCLI", since: Date().addingTimeInterval(-240), cpu: 96),
                Slowed(pid: 4190, start: 0, name: "ffmpeg", since: Date().addingTimeInterval(-420), cpu: 88)]
    let noop = PanelActions(restore: { _ in }, giveBack: {}, openSettings: {}, openActivity: {}, quit: {})
    let cases: [(String, AppModel, NSAppearance.Name)] = [
        ("active-light", AppModel(previewEnabled: true, slowed: jobs), .aqua),
        ("active-dark", AppModel(previewEnabled: true, slowed: jobs), .darkAqua),
        ("calm-light", AppModel(previewEnabled: true), .aqua),
        ("off-light", AppModel(previewEnabled: false), .aqua),
        ("observe-light", AppModel(previewEnabled: true, observeOnly: true), .aqua),
    ]
    for (name, model, appearance) in cases {
        let host = NSHostingView(rootView: PanelView(model: model, actions: noop))
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: appearance)
        w.backgroundColor = .windowBackgroundColor
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        // The captured view has no background of its own (it would be white, unreadable in dark mode),
        // so give it the window color resolved for this appearance.
        var bg = NSColor.windowBackgroundColor.cgColor
        w.effectiveAppearance.performAsCurrentDrawingAppearance { bg = NSColor.windowBackgroundColor.cgColor }
        host.wantsLayer = true
        host.layer?.backgroundColor = bg
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
            }
        }
    }
    exit(0)
}

/// Dev aid: draw the Activity window (three states) and the welcome screen to PNG files, then exit.
/// Uses sample data, starts no engine and touches no saved settings.
func snapshotActivityAndWelcome(prefix: String) -> Never {
    func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to path: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: appearance)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        var bg = NSColor.windowBackgroundColor.cgColor
        w.effectiveAppearance.performAsCurrentDrawingAppearance { bg = NSColor.windowBackgroundColor.cgColor }
        host.wantsLayer = true
        host.layer?.backgroundColor = bg
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    let noActions = ActivityActions(slow: { _, _ in }, restore: { _ in }, protect: { _ in }, unprotect: { _ in }, clearLog: {}, showMenu: { _ in }, setStartup: { _, _ in }, openLoginSettings: {},
                                  trashStorage: { _ in }, revealStorage: { _ in })
    let status = SystemStatus(cpuLoad: 38, cores: 8, memoryUsedGB: 9.8, memoryTotalGB: 16, pressure: .elevated, thermal: .nominal,
                              lowPowerMode: true,
                              battery: BatteryStatus(percent: 63, charging: false, onAC: false, minutesRemaining: 512, health: "Good",
                                                     maxCapacity: "85%", cycles: 670),
                              storageFreeGB: 608, storageTotalGB: 994)
    func row(_ pid: Int32, _ name: String, _ cpu: Double, _ status: JobStatus, _ detail: String,
             access: ManualAccess = .ok, lock: String? = nil, restore: Bool = false, protect: Bool = true, entry: String? = nil) -> ActivityRow {
        ActivityRow(pid: pid, start: 1, name: name, protectName: name, userEntry: entry, cpu: cpu, status: status, detail: detail, access: access,
                    confirmText: nil, lockReason: lock, canRestore: restore, canProtect: protect)
    }
    let rows = [
        row(1, "HandBrakeCLI", 96, .slowed, tr("Slowed %@", ago(Date().addingTimeInterval(-240))), access: .locked, restore: true),
        row(2, "ffmpeg", 88, .watching, tr("Busy for %d of %d seconds", 40, 60)),
        row(3, "Google Chrome Helper (Renderer)", 71, .leftAlone, tr("Never slowed: %@", tr("Browser")), access: .confirm),
        row(4, "ollama", 64, .protected_, tr("Local AI host"), access: .locked, lock: tr("Local AI host"), protect: false),
        row(5, "node", 52, .wouldSlow, tr("Would be slowed"), access: .locked, lock: tr("Turn off Observe only to change jobs")),
        row(6, "python3", 12, .normal, tr("Below the busy threshold")),
        row(7, "Blender", 3, .protected_, tr("On your protected list"), access: .locked, lock: tr("On your protected list"), protect: false, entry: "blender"),
        row(8, "Finder", 1, .protected_, tr("System or this app"), access: .locked, lock: tr("System or this app"), protect: false),
        row(9, "mdworker_shared", 0, .normal, tr("Below the busy threshold")),
    ]
    let log = "2:14:09 PM  SLOWED   HandBrakeCLI (pid 4182) 96%, busy for 60s\n2:11:02 PM  NORMAL   Xcode Build Service (pid 2950) now in the foreground\n1:52:40 PM  START    Apple M1, threshold 50% for 12x5s"
    let size = NSSize(width: 1040, height: 680)
    render(ActivityView(model: ActivityModel(rows: rows, system: status, engineOn: true), actions: noActions), size: size, appearance: .aqua, to: "\(prefix)-activity-light.png")
    render(ActivityView(model: ActivityModel(rows: rows, system: status, engineOn: true), actions: noActions), size: size, appearance: .darkAqua, to: "\(prefix)-activity-dark.png")
    render(ActivityView(model: ActivityModel(rows: [], system: status, engineOn: false), actions: noActions), size: size, appearance: .aqua, to: "\(prefix)-activity-off.png")
    func item(_ label: String, _ name: String, _ dev: String?, _ kind: StartupKind, _ when: String, _ on: Bool?, _ run: Bool?, _ control: StartupControl) -> StartupItem {
        StartupItem(label: label, name: name, developer: dev, kind: kind, startsWhen: when, enabled: on, running: run, control: control, plistPath: "/x")
    }
    let startup = [
        item("com.google.GoogleUpdater.wake", "GoogleUpdater", nil, .userAgent, trkey("On a schedule"), true, false, .toggle),
        item("com.openai.atlas.update-helper", "ChatGPT Atlas", nil, .userAgent, trkey("At login, then on a schedule"), true, false, .toggle),
        item("homebrew.mxcl.ollama", "ollama", nil, .userAgent, trkey("At login, kept running"), false, false, .toggle),
        item("com.grammarly.ProjectLlama.UpdateService", "Grammarly Desktop Update Service", nil, .userAgent, trkey("At login, kept running"), false, false,
             .settingsOnly(trkey("Switched off in System Settings: turn it back on there"))),
        item("com.microsoft.update.agent", "Microsoft AutoUpdate", "Microsoft AutoUpdate", .systemAgent, trkey("At login, then on a schedule"), true, nil,
             .settingsOnly(trkey("Needs an administrator: use System Settings"))),
        item("com.microsoft.fresno", "Microsoft Defender", "Microsoft Defender", .systemDaemon, trkey("At login, kept running"), true, nil, .locked(trkey("Security tool"))),
        item("com.piriform.ccleaner.services.xpc", "CCleaner", "Piriform Ltd", .systemDaemon, trkey("On demand"), true, nil,
             .settingsOnly(trkey("Needs an administrator: use System Settings"))),
        item("com.alexxxela.bgoptimizer", "BG Optimizer", nil, .loginItem, trkey("At login"), true, nil, .locked(trkey("This app: use Launch at login in Settings"))),
        item("com.reverso.launcher", "Reverso", nil, .loginItem, trkey("At login"), true, nil, .settingsOnly(trkey("Managed in System Settings"))),
    ]
    render(ActivityView(model: ActivityModel(rows: rows, system: status, engineOn: true, tab: .startup, startup: startup), actions: noActions), size: size, appearance: .aqua, to: "\(prefix)-activity-startup.png")
    func store(_ name: String, _ sub: String, _ kind: StorageKind, _ mb: Double?, _ note: String, _ arg: String? = nil, lock: String? = nil) -> StorageItem {
        StorageItem(name: name, path: "/Users/you/Library/\(sub)/\(name)", kind: kind, bytes: mb.map { Int64($0 * 1e6) }, note: note, noteArg: arg, lock: lock)
    }
    let storage = [
        store("net.protected.macos.TotalAV", "Application Support", .leftover, 275, StorageScanner.noteLeftover, "protected"),
        store("com.google.Chrome", "Caches", .cache, 812, StorageScanner.noteCache, lock: StorageScanner.lockRunning),
        store("MyApp-bkqvrnhxmq", "Developer/Xcode/DerivedData", .developer, 640, StorageScanner.noteDeveloper),
        store("Homebrew", "Caches", .cache, 188, StorageScanner.noteCache),
        store("Zoom", "Logs", .log, 21, StorageScanner.noteLog),
        store("com.malwarebytes.mbam", "Application Support", .leftover, 0.004, StorageScanner.noteLeftover, "malwarebytes"),
        store("com.eset.agent.finderextension", "Containers", .leftover, nil, StorageScanner.noteLeftover, "eset"),
        store("com.swiftlydetecting.agent.plist", "Preferences", .leftover, 0.004, StorageScanner.noteLeftover, "swiftlydetecting"),
    ]
    render(ActivityView(model: ActivityModel(rows: rows, system: status, engineOn: true, tab: .storage, storage: storage), actions: noActions), size: size, appearance: .aqua, to: "\(prefix)-activity-storage.png")
    render(ActivityView(model: ActivityModel(rows: rows, system: status, engineOn: true, tab: .log, log: log), actions: noActions), size: size, appearance: .aqua, to: "\(prefix)-activity-log.png")
    render(SettingsView(model: AppModel(previewEnabled: true), actions: SettingsActions(setLogin: { _ in }, giveBack: {})),
           size: NSSize(width: 520, height: 560), appearance: .aqua, to: "\(prefix)-settings-light.png")
    render(FirstRunView(draft: FirstRunDraft(), model: AppModel(previewEnabled: true), onStart: {}), size: NSSize(width: 540, height: 700), appearance: .aqua, to: "\(prefix)-welcome-light.png")
    render(FirstRunView(draft: FirstRunDraft(), model: AppModel(previewEnabled: true), onStart: {}), size: NSSize(width: 540, height: 700), appearance: .darkAqua, to: "\(prefix)-welcome-dark.png")
    exit(0)
}

// Headless mode (for testing from Terminal): BGOptimizer --headless [--threshold N] [--sustain N] [--interval S] [--seconds S] [--dry-run]
func runHeadless(_ args: [String]) -> Never {
    func value(_ flag: String) -> Double? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } }
    var cfg = Config()
    if let v = value("--threshold") { cfg.threshold = v }
    if let v = value("--sustain") { cfg.sustain = Int(v) }
    if let v = value("--interval") { cfg.interval = v }
    cfg.dryRun = args.contains("--dry-run")
    let engine = Engine(cfg, ActionLog(echo: true))
    engine.recoverFromCrash()
    installSignalHandlers(engine)
    engine.start()
    if let secs = value("--seconds") {
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { engine.shutdownSync(); exit(0) }
    }
    RunLoop.main.run()
    exit(0)
}

// Command line: BGOptimizer --login on|off|status   (same switch as "Launch at login" in the app)
if let i = CommandLine.arguments.firstIndex(of: "--login"), i + 1 < CommandLine.arguments.count {
    let svc = SMAppService.mainApp
    switch CommandLine.arguments[i + 1] {
    case "on": try? svc.register()
    case "off": try? svc.unregister()
    default: break
    }
    print("launch at login:", svc.status == .enabled ? "on" : "off")
    exit(0)
}

// Dev aid: --lang en|uk forces a language for the snapshot options below.
if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count {
    L10n.apply(AppLanguage(rawValue: CommandLine.arguments[i + 1]) ?? .system)
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-windows"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    snapshotActivityAndWelcome(prefix: CommandLine.arguments[i + 1])
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-panel"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    snapshotPanel(prefix: CommandLine.arguments[i + 1])
}

if CommandLine.arguments.contains("--headless") { runHeadless(CommandLine.arguments) }
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
