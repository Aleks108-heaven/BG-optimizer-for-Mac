import AppKit
import Combine
import SwiftUI

/// What the Activity window can ask for. The engine and the app decide again; these only carry out your request.
struct ActivityActions {
    var slow: (ActivityRow, Bool) -> Void       // job, you confirmed the warning
    var restore: (Int32) -> Void
    var protect: (String) -> Void
    var unprotect: (String) -> Void
    var clearLog: () -> Void
    var showMenu: (ActivityRow) -> Void         // opens the row's menu at the mouse
    var setStartup: (StartupItem, Bool) -> Void // switch a startup item of yours on or off for the next login
    var openLoginSettings: () -> Void           // System Settings > Login Items & Extensions
    var trashStorage: (StorageItem) -> Void     // move one item of the Storage tab to the Trash (you confirmed)
    var revealStorage: (StorageItem) -> Void    // show it in Finder
}

/// State of the Activity window. The engine feeds `rows`; the Mac's own status is read here every 5 seconds while the window is open.
final class ActivityModel: ObservableObject {
    enum Tab: Int { case processes, startup, storage, log, drivers }

    @Published var tab: Tab = .processes
    @Published var rows: [ActivityRow] = []
    @Published var ownCount = 0
    @Published var updated: Date?
    @Published var system: SystemStatus?
    @Published var logText = ""
    @Published var query = ""
    @Published var showLegend = false
    @Published var engineOn = false
    @Published var observeOnly = false
    @Published var language = ""        // changes when the app language changes, so the window redraws
    @Published var sortOrder = [KeyPathComparator(\ActivityRow.cpu, order: .reverse)]
    @Published var onlyActive = false   // hide jobs under 1% CPU
    @Published var pending: ActivityRow?        // a job waiting for your confirmation before it is slowed
    @Published var askClearLog = false
    @Published var startup: [StartupItem] = []
    @Published var startupLoading = false
    @Published var startupSort = [KeyPathComparator(\StartupItem.kindRank), KeyPathComparator(\StartupItem.name)]
    @Published var drivers: [DriverItem] = []
    @Published var driversLoading = false
    @Published var driversReadFailed = false    // macOS did not list the system extensions, so the list may be incomplete
    @Published var driversSort = [KeyPathComparator(\DriverItem.statusRank), KeyPathComparator(\DriverItem.name)]
    @Published var openBanners: Set<Tab> = []   // tabs whose explanation is expanded (it starts as one line)
    @Published var storage: [StorageItem] = []
    @Published var storageLoading = false
    @Published var storageSort = [KeyPathComparator(\StorageItem.sortBytes, order: .reverse)]
    @Published var hideSmall = true             // hide caches and logs under 1 MB (leftovers are always shown)
    @Published var pendingTrash: StorageItem?   // an item waiting for your confirmation before it goes to the Trash
    @Published var notice: String?              // result of your last action, shown for a few seconds
    @Published var noticeIsError = false
    private var noticeToken = UUID()

    var logProvider: () -> String = { "" }
    private var timer: Timer?
    var isRefreshing: Bool { timer != nil }
    private let reader = SystemReader()
    private let queue = DispatchQueue(label: "bgopt.system")

    init() {}

    /// For snapshots only.
    init(rows: [ActivityRow], system: SystemStatus, engineOn: Bool, tab: Tab = .processes, log: String = "", startup: [StartupItem] = [],
         storage: [StorageItem] = [], drivers: [DriverItem] = []) {
        self.startup = startup
        self.storage = storage
        self.drivers = drivers
        self.rows = rows
        self.ownCount = 312
        self.updated = Date()
        self.system = system
        self.engineOn = engineOn
        self.tab = tab
        self.logText = log
    }

    var filtered: [ActivityRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = rows
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) } }
        if onlyActive { list = list.filter { $0.cpu >= 1 || $0.status == .slowed } }
        return list.sorted(using: sortOrder)
    }

    func showNotice(_ text: String, error: Bool) {
        notice = text
        noticeIsError = error
        let token = UUID()
        noticeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.noticeToken == token { self?.notice = nil }
        }
    }

    func start() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }   // the first CPU reading needs two samples
        timer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        queue.async {
            let s = self.reader.read()
            DispatchQueue.main.async { self.system = s }
        }
        if tab == .log { logText = logProvider() }
    }

    func toggleBanner(_ t: Tab) {
        if openBanners.contains(t) { openBanners.remove(t) } else { openBanners.insert(t) }
    }

    func select(_ t: Tab) {
        tab = t
        if t == .log { logText = logProvider() }
        if t == .startup { refreshStartup() }
        if t == .storage { refreshStorage() }
        if t == .drivers { refreshDrivers() }
    }

    private let driversQueue = DispatchQueue(label: "bgopt.drivers")
    private var driversToken = UUID()

    /// Reading the drivers takes a second or two (systemextensionsctl), so it runs in the background and only when the tab is opened or Refresh is pressed.
    func refreshDrivers() {
        let token = UUID()
        driversToken = token
        driversLoading = true
        driversQueue.async {
            let read = DriverScanner.read()
            DispatchQueue.main.async {
                guard self.driversToken == token else { return }        // a newer read is on its way
                self.drivers = read.items
                self.driversReadFailed = !read.extensionsRead
                self.driversLoading = false
            }
        }
    }

    var filteredDrivers: [DriverItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? drivers : drivers.filter { $0.name.lowercased().contains(q) || $0.identifier.lowercased().contains(q) }
        return list.sorted(using: driversSort)
    }

    private let startupQueue = DispatchQueue(label: "bgopt.startup")

    /// Reading the startup list takes a few seconds (sfltool), so it runs in the background and only when asked for.
    func refreshStartup() {
        startupLoading = true
        startupQueue.async {
            let items = StartupReader.read()
            DispatchQueue.main.async { self.startup = items; self.startupLoading = false }
        }
    }

    private let storageQueue = DispatchQueue(label: "bgopt.storage")
    private var storageToken = UUID()

    /// Looking through the Library takes a few seconds, so it runs in the background and only when the tab is opened or Refresh is pressed.
    func refreshStorage() {
        let token = UUID()
        storageToken = token
        storageLoading = true
        storageQueue.async {
            let items = StorageScanner.scan(ctx: StorageScanner.currentContext())
            DispatchQueue.main.async {
                guard self.storageToken == token else { return }       // a newer read is on its way
                self.storage = items
                self.storageLoading = false
            }
        }
    }

    var filteredStorage: [StorageItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = storage
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) } }
        if hideSmall { list = list.filter { $0.kind == .leftover || ($0.bytes ?? 0) >= 1_000_000 } }
        return list.sorted(using: storageSort)
    }

    /// Show a switch's new position at once, before the slower re-read finishes.
    func setStartupEnabled(_ id: String, _ on: Bool) {
        if let i = startup.firstIndex(where: { $0.id == id }) { startup[i].enabled = on }
    }

    var filteredStartup: [StartupItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? startup : startup.filter { $0.name.lowercased().contains(q) || $0.label.lowercased().contains(q) }
        return list.sorted(using: startupSort)
    }
}

// MARK: - pieces

private struct StatusChip: View {
    let status: JobStatus

    private var look: (icon: String, label: String, bg: Color, ink: Color) {
        switch status {
        case .slowed: return ("arrow.down", trkey("Slowed"), .slowBg, .slowInk)
        case .watching: return ("clock", trkey("Watching"), .neuBg, .neuInk)
        case .wouldSlow: return ("eye", trkey("Would slow"), .slowBg, .slowInk)
        case .leftAlone: return ("minus.circle", trkey("Skipped"), .neuBg, .neuInk)
        case .protected_: return ("lock", trkey("Protected"), .protBg, .protInk)
        case .normal: return ("checkmark", trkey("Normal job"), .neuBg, .neuInk)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: look.icon).font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            Text(tr(look.label)).font(.caption.bold())
        }
        .foregroundStyle(look.ink)
        .padding(.horizontal, 9).padding(.vertical, 2)
        .background(Capsule().fill(look.bg))
    }
}

private enum Level { case ok, attention, alert }

private struct Tile: View {
    let title: String
    let value: String
    let caption: String
    var extra: String? = nil
    var level: Level = .ok
    var wide = false                // caption and extra side by side (used for the battery)

    fileprivate var glyph: (String, Color) {
        switch level {
        case .ok: return ("checkmark.circle", .calmInk)
        case .attention: return ("exclamationmark.triangle", .slowInk)
        case .alert: return ("exclamationmark.octagon", .warnInk)
        }
    }

    var body: some View {
        if wide { wideBody } else { normalBody }
    }

    private var wideBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased(with: L10n.locale)).font(.caption2.bold()).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: glyph.0).foregroundStyle(glyph.1).accessibilityHidden(true)
                    Text(value).font(.title3.bold())
                }
                Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let extra = extra {
                    Text(extra).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
    }

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased(with: L10n.locale)).font(.caption2.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: glyph.0).foregroundStyle(glyph.1).accessibilityHidden(true)
                Text(value).font(.title3.bold())
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let extra = extra { Text(extra).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
    }
}

/// An explanation that takes one line until you ask for more: it teaches a tab once, and must not keep taking the table's room.
private struct InfoBanner<Trailing: View>: View {
    let summary: String
    let details: String
    let open: Bool
    let toggle: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Label(open ? details : summary, systemImage: "info.circle")       // the full text replaces the summary, so nothing is said twice
                .font(.callout).foregroundStyle(Color.neuInk).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(open ? tr("Less") : tr("More"), action: toggle)
                .buttonStyle(.link)
                .accessibilityLabel(open ? tr("Hide details") : tr("Show details"))
            trailing()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.neuBg))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

/// One reading of the status strip: a symbol (so the state is not only a colour), the name, the value; the details in the tooltip.
private struct StatusPill: View {
    let tile: Tile

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tile.glyph.0).foregroundStyle(tile.glyph.1).accessibilityHidden(true)
            (Text(tile.title).foregroundColor(.secondary) + Text(" " + tile.value).bold())
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
        .help([tile.caption, tile.extra].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
        .accessibilityElement(children: .combine)
    }
}

private func duration(_ minutes: Int) -> String {
    minutes >= 60 ? tr("%d h %d min", minutes / 60, minutes % 60) : tr("%d min", minutes)
}

private func gb(_ v: Double) -> String { v >= 100 ? tr("%.0f GB", v) : tr("%.1f GB", v) }

/// Battery health words come from System Information in English; show ours when we know them.
private let knownHealth = [trkey("health.Good"), trkey("health.Normal"), trkey("health.Fair"), trkey("health.Poor"),
                           trkey("health.Check Battery"), trkey("health.Service Recommended"),
                           trkey("health.Replace Soon"), trkey("health.Replace Now")]

private func healthText(_ h: String) -> String {
    let key = "health." + h
    let t = L10n.string(key)
    return t == key ? h : t
}

// MARK: - window

struct ActivityView: View {
    @ObservedObject var model: ActivityModel
    let actions: ActivityActions

    /// Below this height the big tiles would leave the table almost no room (the window can be made about 600 x 440).
    private static let roomyHeight: CGFloat = 600

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if model.tab == .processes && geo.size.height >= Self.roomyHeight { tiles.padding(.horizontal, 16).padding(.top, 14) }
                else { statusStrip.padding(.horizontal, 16).padding(.top, 12) }
                toolbar.padding(.horizontal, 16).padding(.vertical, 10)
                if let text = model.notice { noticeBar(text) }
                switch model.tab {
                case .processes: processes
                case .startup: startupView
                case .drivers: driversView
                case .storage: storageView
                case .log: logView
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .id(model.language)
        .confirmationDialog(tr("Slow down %@?", model.pending?.name ?? ""),
                            isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
                            titleVisibility: .visible, presenting: model.pending) { row in
            Button(tr("Slow down anyway"), role: .destructive) { actions.slow(row, true); model.pending = nil }
            Button(tr("Cancel"), role: .cancel) { model.pending = nil }
        } message: { row in
            Text(row.confirmText ?? "")
        }
        .confirmationDialog(tr("Move “%@” to the Trash?", model.pendingTrash?.name ?? ""),
                            isPresented: Binding(get: { model.pendingTrash != nil }, set: { if !$0 { model.pendingTrash = nil } }),
                            titleVisibility: .visible, presenting: model.pendingTrash) { item in
            Button(tr("Move to Trash"), role: .destructive) { actions.trashStorage(item); model.pendingTrash = nil }
            Button(tr("Cancel"), role: .cancel) { model.pendingTrash = nil }
        } message: { item in
            Text(trashMessage(item))
        }
        .confirmationDialog(tr("Clear the activity log?"), isPresented: $model.askClearLog, titleVisibility: .visible) {
            Button(tr("Clear log"), role: .destructive) { actions.clearLog() }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(tr("All lines are deleted. This cannot be undone."))
        }
    }

    private func noticeBar(_ text: String) -> some View {
        Label(text, systemImage: model.noticeIsError ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(model.noticeIsError ? Color.warnBg : Color.calmBg))
            .foregroundStyle(model.noticeIsError ? Color.warnInk : Color.calmInk)
            .padding(.horizontal, 16).padding(.bottom, 8)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: tiles

    @ViewBuilder private var tiles: some View {
        if let s = model.system {
            VStack(spacing: 10) {
                // Four across when there is room, two by two when the window is small.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { smallTiles(s) }
                        .fixedSize(horizontal: false, vertical: true)       // all four take the height of the tallest
                        .frame(minWidth: 700)
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 10) { smallTiles(s, first: 2) }.fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 10) { smallTiles(s, first: 2, skip: 2) }.fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let b = s.battery { batteryTile(b, s) }
            }
        } else {
            Text(tr("Reading this Mac's status…")).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70)
        }
    }

    /// CPU, memory, thermal, storage: all four, or `first` of them after skipping `skip`.
    @ViewBuilder private func smallTiles(_ s: SystemStatus, first: Int = 4, skip: Int = 0) -> some View {
        ForEach(Array(fourTiles(s).dropFirst(skip).prefix(first).enumerated()), id: \.offset) { _, tile in tile }
    }

    private func fourTiles(_ s: SystemStatus) -> [Tile] {
        [
            Tile(title: tr("CPU load"), value: String(format: "%.0f%%", s.cpuLoad), caption: tr("across %d cores", s.cores),
                 level: s.cpuLoad >= 90 ? .attention : .ok),
            Tile(title: tr("Memory"), value: tr(s.pressure.label), caption: tr("%@ of %@ in use", gb(s.memoryUsedGB), gb(s.memoryTotalGB)),
                 extra: s.pressure == .normal ? nil : tr("macOS is working to free memory"),
                 level: s.pressure == .normal ? .ok : (s.pressure == .elevated ? .attention : .alert)),
            thermalTile(s),
            Tile(title: tr("Storage"), value: tr("%@ free", gb(s.storageFreeGB)), caption: tr("of %@", gb(s.storageTotalGB)),
                 level: s.storageFreeGB < 20 ? .attention : .ok),
        ]
    }

    /// The same readings in one line (two when the window is narrow), for when the big tiles would push the table out of view.
    /// The longer wording of each tile is in its tooltip. The battery line adds the time left, which is what you usually want from it.
    @ViewBuilder private var statusStrip: some View {
        if let s = model.system {
            let pills = stripTiles(s)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { ForEach(Array(pills.enumerated()), id: \.offset) { _, t in StatusPill(tile: t) }; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 16) { ForEach(Array(pills.prefix(3).enumerated()), id: \.offset) { _, t in StatusPill(tile: t) }; Spacer(minLength: 0) }
                    HStack(spacing: 16) { ForEach(Array(pills.dropFirst(3).enumerated()), id: \.offset) { _, t in StatusPill(tile: t) }; Spacer(minLength: 0) }
                }
            }
        } else {
            Text(tr("Reading this Mac's status…")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stripTiles(_ s: SystemStatus) -> [Tile] {
        var list = fourTiles(s)
        if let b = s.battery {
            let t = batteryTile(b, s)
            let left = (!b.onAC && !b.charging) ? b.minutesRemaining.map { " · " + duration($0) } : nil
            list.append(Tile(title: t.title, value: t.value + (left ?? ""), caption: t.caption, extra: t.extra, level: t.level))
        }
        return list
    }

    private func thermalTile(_ s: SystemStatus) -> Tile {
        let title = tr("Thermal state")
        switch s.thermal {
        case .nominal: return Tile(title: title, value: tr("Nominal"), caption: tr("Not throttled"))
        case .fair: return Tile(title: title, value: tr("Fair"), caption: tr("Slightly warm"), level: .attention)
        case .serious: return Tile(title: title, value: tr("Serious"), caption: tr("Hot: macOS is reducing performance"), level: .alert)
        case .critical: return Tile(title: title, value: tr("Critical"), caption: tr("Very hot: performance is cut hard"), level: .alert)
        @unknown default: return Tile(title: title, value: tr("Unknown"), caption: "")
        }
    }

    private func batteryTile(_ b: BatteryStatus, _ s: SystemStatus) -> Tile {
        var state: String
        if b.charging { state = tr("Charging") + (b.minutesRemaining.map { tr(", %@ to full", duration($0)) } ?? "") }
        else if b.onAC { state = tr("Plugged in") }
        else { state = tr("On battery") + (b.minutesRemaining.map { tr(", %@ left", duration($0)) } ?? "") }
        if s.lowPowerMode { state += tr(". Low Power Mode on") }
        var health: String?
        if let h = b.health {
            health = tr("Health: %@", healthText(h)) + (b.maxCapacity.map { tr(", %@ of original capacity", $0) } ?? "")
                + (b.cycles.map { tr(", %d cycles", $0) } ?? "")
        }
        let low = !b.onAC && b.percent <= 20
        let poor = b.health.map { $0 != "Good" && $0 != "Normal" } ?? false
        return Tile(title: tr("Battery"), value: "\(b.percent)%", caption: state, extra: health, level: (low || poor) ? .attention : .ok, wide: true)
    }

    // MARK: toolbar

    private var viewPicker: some View {
        Picker(tr("View"), selection: Binding(get: { model.tab }, set: { model.select($0) })) {
            Text(tr("Processes")).tag(ActivityModel.Tab.processes)
            Text(tr("Startup")).tag(ActivityModel.Tab.startup)
            Text(tr("Drivers")).tag(ActivityModel.Tab.drivers)
            Text(tr("Storage")).tag(ActivityModel.Tab.storage)
            Text(tr("Log")).tag(ActivityModel.Tab.log)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()                    // its natural width, so it lines up with the content below instead of floating in a wider frame
    }

    /// The hide-idle switch and the filter. They go on a second line when the window is too narrow for everything on one.
    @ViewBuilder private var viewOptions: some View {
        if model.tab != .log {
            if model.tab == .processes { Toggle(tr("Hide idle processes"), isOn: $model.onlyActive).toggleStyle(.checkbox) }
            TextField(tr("Filter by name"), text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 110, maxWidth: 200)
                .accessibilityLabel(tr("Filter by name"))
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack { viewPicker; Spacer(); viewOptions }
            VStack(alignment: .leading, spacing: 8) {
                viewPicker
                HStack { Spacer(); viewOptions }
            }
        }
    }

    // MARK: processes

    private var banner: String? {
        if !model.engineOn { return tr("BG Optimizer is switched off, so jobs are not being watched. Switch it on in the menu-bar panel.") }
        if model.observeOnly { return tr("Observe only: nothing is being slowed. Jobs marked \"Would slow\" are what it would have changed.") }
        return nil
    }

    private var processes: some View {
        VStack(spacing: 0) {
            if let text = banner {
                Label(text, systemImage: "info.circle")
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.neuBg))
                    .foregroundStyle(Color.neuInk)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.filtered.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filtered, sortOrder: $model.sortOrder) {
                    TableColumn(tr("Process"), value: \.name) { row in
                        Text(row.name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail).help(row.name)
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn(tr("CPU (of one core)"), value: \.cpu) { row in
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(nsColor: .quaternaryLabelColor)).frame(width: 52, height: 6)
                                Capsule().fill(Color.secondary).frame(width: CGFloat(min(row.cpu, 100)) / 100 * 52, height: 6)
                            }
                            .accessibilityHidden(true)
                            Text(String(format: "%.0f%%", row.cpu)).monospacedDigit()
                        }
                    }
                    .width(min: 100, ideal: 110)
                    TableColumn(tr("Memory"), value: \.memBytes) { row in
                        Text(row.memBytes == 0 ? "—" : sizeText(Int64(row.memBytes))).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 85)
                    TableColumn(tr("Status"), value: \.statusRank) { row in StatusChip(status: row.status) }
                        .width(min: 105, ideal: 120)
                    TableColumn(tr("Details")) { row in
                        Text(row.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(row.detail)
                    }
                    TableColumn("") { row in actionMenu(row) }
                        .width(34)
                }
            }
            footer
        }
    }

    /// The "…" button of a row. The menu itself is a native popup opened at the mouse (see AppDelegate.showRowMenu);
    /// a SwiftUI Menu inside a Table cell opened far away from the row.
    private func actionMenu(_ row: ActivityRow) -> some View {
        Button { actions.showMenu(row) } label: { Image(systemName: "ellipsis.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Actions for %@", row.name))
            .help(tr("Actions for %@", row.name))
    }

    private var emptyMessage: String {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { return tr("No job matches that name.") }
        if !model.engineOn { return tr("Nothing to show while it is switched off.") }
        if model.updated == nil { return tr("Collecting the first sample (a few seconds)…") }
        return tr("Nothing is using much CPU right now.")
    }

    private var footer: some View {
        HStack {
            Text(model.engineOn
                 ? tr("Your processes: %d. Updated every 5 seconds. Click Memory to see which use the most.", model.ownCount)
                 : tr("Updated every 5 seconds while it is on."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(tr("What do the statuses mean?")) { model.showLegend.toggle() }
                .buttonStyle(.link)
                .popover(isPresented: $model.showLegend) { legend }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(.slowed, tr("Running at low priority until it calms down or you open it."))
            legendRow(.watching, tr("Busy, but not for long enough yet."))
            legendRow(.wouldSlow, tr("Observe only: it would be slowed."))
            legendRow(.leftAlone, tr("Never slowed automatically: browsers, calls, audio, editors, the app in front, or anything keeping the Mac awake. You can still slow one yourself, after a warning."))
            legendRow(.protected_, tr("System, security, local AI, or an app on your list. Cannot be slowed, even by you."))
            legendRow(.normal, tr("Below the busy threshold."))
        }
        .padding(14)
        .frame(width: 460)
    }

    private func legendRow(_ s: JobStatus, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatusChip(status: s).frame(width: 110, alignment: .leading)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: startup

    private func kindChip(_ k: StartupKind) -> some View {
        let label: String
        switch k {
        case .userAgent: label = tr("Your agent")
        case .systemAgent: label = tr("System agent")
        case .systemDaemon: label = tr("System daemon")
        case .loginItem: label = tr("Login item")
        }
        return Text(label).font(.caption.bold()).foregroundStyle(Color.neuInk)
            .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Color.neuBg))
    }

    @ViewBuilder private func startupControl(_ item: StartupItem) -> some View {
        switch item.control {
        case .toggle:
            Toggle("", isOn: Binding(get: { item.enabled ?? true }, set: { actions.setStartup(item, $0) }))
                .toggleStyle(.switch).labelsHidden()
                .accessibilityLabel(tr("Start “%@” at login", item.name))
        case .settingsOnly(let why):
            HStack(spacing: 8) {
                Text(item.enabled.map { $0 ? tr("On") : tr("Off") } ?? "—").font(.caption.bold()).foregroundStyle(.secondary).frame(minWidth: 26, alignment: .leading)
                Button(tr("Settings…"), action: actions.openLoginSettings).buttonStyle(.link).help(tr(why))
            }
        case .locked(let why):
            HStack(spacing: 4) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text(item.enabled.map { $0 ? tr("On") : tr("Off") } ?? "—").font(.caption.bold())
            }
            .foregroundStyle(Color.protInk).padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Color.protBg))
            .help(tr(why))
        }
    }

    private var startupView: some View {
        VStack(spacing: 0) {
            InfoBanner(summary: tr("Switch your own login items off or on here. Nothing that is running gets stopped."),
                       details: tr("Items from your own Library can be switched here. Switching one off only stops it from starting at the next login: nothing running is stopped or deleted, and you can switch it back on. System-wide items need an administrator, so change those in System Settings."),
                       open: model.openBanners.contains(.startup), toggle: { model.toggleBanner(.startup) }) {
                Button(tr("Open Login Items settings"), action: actions.openLoginSettings)
            }
            if model.startup.isEmpty {
                Text(model.startupLoading ? tr("Reading startup items (a few seconds)…") : tr("Nothing starts by itself."))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filteredStartup, sortOrder: $model.startupSort) {
                    TableColumn(tr("Item"), value: \.name) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                            Text(item.developer.map { "\($0) · \(item.label)" } ?? item.label)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        .help(item.label)
                    }
                    .width(min: 170, ideal: 250)
                    TableColumn(tr("Starts")) { item in Text(tr(item.startsWhen)).lineLimit(1).truncationMode(.tail).help(tr(item.startsWhen)) }
                        .width(min: 110, ideal: 190)
                    TableColumn(tr("Kind"), value: \.kindRank) { item in kindChip(item.kind) }
                        .width(min: 100, ideal: 130)
                    TableColumn(tr("Now")) { item in
                        Text(item.running.map { $0 ? tr("Running") : tr("Not running") } ?? "—").foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn(tr("Start at login")) { item in startupControl(item) }
                        .width(min: 120, ideal: 160)
                }
            }
            HStack {
                Text(tr("Startup items: %d. Switching one off never stops what is running.", model.startup.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.startupLoading { ProgressView().controlSize(.small) }
                Button(tr("Refresh")) { model.refreshStartup() }.buttonStyle(.link)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    // MARK: drivers

    private func driverKindChip(_ k: DriverKind) -> some View {
        let label: String
        switch k {
        case .systemExtension: label = tr("System extension")
        case .kernelExtension: label = tr("Kernel extension")
        case .helperTool: label = tr("Helper tool")
        }
        return Text(label).font(.caption.bold()).foregroundStyle(Color.neuInk)
            .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Color.neuBg))
    }

    private func driverStatusChip(_ s: DriverStatus) -> some View {
        let look: (icon: String, label: String, bg: Color, ink: Color)
        switch s {
        case .probablyUnused: look = ("exclamationmark.triangle", trkey("Probably not in use"), .slowBg, .slowInk)
        case .makerAppMissing: look = ("questionmark.circle", trkey("Maker's app not found"), .slowBg, .slowInk)
        case .switchedOff: look = ("power", trkey("Switched off"), .neuBg, .neuInk)
        case .pending: look = ("clock", trkey("Waiting"), .neuBg, .neuInk)
        case .legacy: look = ("clock.arrow.circlepath", trkey("Old type"), .slowBg, .slowInk)
        case .enabled: look = ("checkmark", trkey("Enabled"), .calmBg, .calmInk)
        case .installed: look = ("shippingbox", trkey("Installed"), .neuBg, .neuInk)
        }
        return HStack(spacing: 4) {
            Image(systemName: look.icon).font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            Text(tr(look.label)).font(.caption.bold())
        }
        .foregroundStyle(look.ink)
        .padding(.horizontal, 9).padding(.vertical, 2)
        .background(Capsule().fill(look.bg))
    }

    private func driverDetail(_ item: DriverItem) -> String {
        item.detailArg.map { tr(item.detail, $0) } ?? tr(item.detail)
    }

    private var driversView: some View {
        VStack(spacing: 0) {
            InfoBanner(summary: tr("Read only: drivers are listed here, never removed by this app."),
                       details: tr("Read only: this app does not remove drivers, because removing one needs an administrator and can break the software that uses it. “Probably not in use” means it is switched off and no app from the same maker is installed. Only the maker can say whether a driver is out of date, so compare the version with the maker's website. To remove one, use the maker's uninstaller; System Settings can switch an extension off. Kernel extensions are the old kind of driver, and Apple silicon Macs load them only with reduced security."),
                       open: model.openBanners.contains(.drivers), toggle: { model.toggleBanner(.drivers) }) {
                Button(tr("Open Login Items settings"), action: actions.openLoginSettings)
            }
            if model.driversReadFailed && !model.driversLoading {
                Label(tr("macOS did not list the system extensions (the read failed or timed out), so some drivers may be missing here."), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Color.slowInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.filteredDrivers.isEmpty {
                Text(model.driversLoading ? tr("Reading drivers (a few seconds)…")
                     : (model.query.trimmingCharacters(in: .whitespaces).isEmpty ? tr("No third-party drivers found.") : tr("No driver matches that name.")))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filteredDrivers, sortOrder: $model.driversSort) {
                    TableColumn(tr("Item"), value: \.name) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                            Text(item.identifier).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        .help(item.identifier)
                    }
                    .width(min: 160, ideal: 210)
                    TableColumn(tr("Status"), value: \.statusRank) { item in driverStatusChip(item.status) }
                        .width(min: 150, ideal: 170)
                    TableColumn(tr("Kind"), value: \.kindRank) { item in driverKindChip(item.kind) }
                        .width(min: 110, ideal: 120)
                    TableColumn(tr("Version or date")) { item in
                        Text(item.info ?? "—").monospacedDigit().foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(item.info ?? "")
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn(tr("Details")) { item in
                        Text(driverDetail(item)).font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail).help(driverDetail(item))
                    }
                }
            }
            HStack {
                Text(tr("Drivers: %d. Nothing is changed here.", model.drivers.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.driversLoading { ProgressView().controlSize(.small) }
                Button(tr("Refresh")) { model.refreshDrivers() }.buttonStyle(.link)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    // MARK: storage

    private func sizeText(_ b: Int64) -> String {
        let v = Double(b)
        if v >= 1e9 { return tr("%.1f GB", v / 1e9) }
        if v >= 1e6 { return tr("%.0f MB", v / 1e6) }
        return tr("%.0f KB", max(v, 1) / 1e3)
    }

    private func storageDetail(_ item: StorageItem) -> String {
        if let lock = item.lock { return tr(lock) }
        return item.noteArg.map { tr(item.note, $0) } ?? tr(item.note)
    }

    private func trashMessage(_ item: StorageItem) -> String {
        var parts: [String] = []
        if let b = item.bytes { parts.append(tr("Size: %@.", (item.approximate ? "≥ " : "") + sizeText(b))) }
        parts.append(storageDetail(item))
        parts.append(tr("It stays in the Trash until you empty it, so you can put it back."))
        return parts.joined(separator: "\n\n")
    }

    private func storageKindChip(_ k: StorageKind) -> some View {
        let label: String
        switch k {
        case .cache: label = tr("Cache")
        case .log: label = tr("Log files")
        case .developer: label = tr("Developer")
        case .leftover: label = tr("Possible leftover")
        }
        let leftover = k == .leftover
        return Text(label).font(.caption.bold()).foregroundStyle(leftover ? Color.slowInk : Color.neuInk)
            .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(leftover ? Color.slowBg : Color.neuBg))
    }

    private func storageButtons(_ item: StorageItem) -> some View {
        let why: String? = model.observeOnly ? tr("Turn off Observe only to change files") : item.lock.map { tr($0) }
        return HStack(spacing: 8) {
            Button { actions.revealStorage(item) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(tr("Reveal in Finder"))
                .accessibilityLabel(tr("Reveal “%@” in Finder", item.name))
            Button { model.pendingTrash = item } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(why != nil)
                .help(why ?? tr("Move to Trash…"))
                .accessibilityLabel(tr("Move “%@” to the Trash?", item.name))
        }
    }

    private var storageView: some View {
        VStack(spacing: 0) {
            InfoBanner(summary: tr("Nothing is deleted automatically: you choose each item, and the Trash can undo it."),
                       details: tr("Only your own Library is listed. Nothing is deleted automatically: you choose each item, and Move to Trash can be undone from the Trash. System-wide files in /Library are never touched here."),
                       open: model.openBanners.contains(.storage), toggle: { model.toggleBanner(.storage) }) {
                Toggle(tr("Hide items under 1 MB"), isOn: $model.hideSmall).toggleStyle(.checkbox)
            }
            if model.observeOnly {
                Label(tr("Observe only: you can look, but not move anything. Turn it off in Settings to move items to the Trash."), systemImage: "eye")
                    .font(.callout).foregroundStyle(Color.neuInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if model.filteredStorage.isEmpty {
                Text(model.storageLoading ? tr("Reading storage (a few seconds)…")
                     : (model.query.trimmingCharacters(in: .whitespaces).isEmpty ? tr("Nothing to show here.") : tr("No item matches that name.")))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filteredStorage, sortOrder: $model.storageSort) {
                    TableColumn(tr("Item"), value: \.name) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                            Text((item.path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        .help(item.path)
                    }
                    .width(min: 170, ideal: 250)
                    TableColumn(tr("Kind"), value: \.kindRank) { item in storageKindChip(item.kind) }
                        .width(min: 110, ideal: 140)
                    TableColumn(tr("Size"), value: \.sortBytes) { item in
                        Text(item.bytes.map { (item.approximate ? "≥ " : "") + sizeText($0) } ?? "—")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .help(item.bytes == nil ? tr("Size not read: macOS keeps other apps' containers closed.") : "")
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn(tr("Details")) { item in
                        Text(storageDetail(item)).font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail).help(storageDetail(item))
                    }
                    TableColumn("") { item in storageButtons(item) }
                        .width(56)
                }
            }
            HStack {
                Text(tr("Items: %d. Nothing is deleted automatically.", model.storage.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.storageLoading { ProgressView().controlSize(.small) }
                Button(tr("Refresh")) { model.refreshStorage() }.buttonStyle(.link)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    // MARK: log

    private var logView: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(model.logText.isEmpty ? tr("Nothing logged yet.") : model.logText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            .padding(.horizontal, 16)
            HStack {
                Text(tr("Kept in ~/Library/Logs/BGOptimizer, rolls over at 1 MB. Log lines are always in English."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Clear log…")) { model.askClearLog = true }
                Button(tr("Open log file")) { NSWorkspace.shared.open(ActionLog.fileURL) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}
