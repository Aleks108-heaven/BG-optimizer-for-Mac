import Foundation
import IOKit.ps

// Battery history: how fast the battery drains while the Mac is awake and while it sleeps. READ ONLY.
//
// The source is the power log macOS keeps itself (`pmset -g log`: about the last week, readable by any user). Every sleep and wake
// in it carries the battery percentage, so a night that happened before this feature existed can be shown, and nothing has to run
// in the background to collect it. The log is not documented as a stable format, so the parser accepts only the lines it fully
// understands and ignores the rest; a Mac whose log looks different simply shows no history.
//
// A sleep is a chain: one real sleep (the lid closed, or idle), then many "dark wakes" of a few seconds each (maintenance, push
// notifications) with the Mac asleep in between, then one real wake. The whole chain is ONE asleep session; the dark wakes are
// counted inside it, because they are part of why a sleeping Mac still uses a little battery.

// MARK: what is read

enum PowerEventKind { case sleep, wake, darkWake }

struct PowerEvent: Equatable {
    var date: Date
    var kind: PowerEventKind
    var percent: Int?          // the battery percentage on that log line
    var onAC: Bool?            // "Using AC" or "Using BATT"; nil if the line does not say
    var reason: String         // for a Sleep line: why ("Clamshell Sleep", "Idle Sleep"); empty otherwise
}

// MARK: what is shown

enum PowerState { case awake, asleep }

struct PowerSession: Identifiable, Equatable {
    var id: Int
    var state: PowerState
    var start: Date
    var end: Date
    var startPercent: Int?
    var endPercent: Int?
    var startOnAC: Bool?
    var endOnAC: Bool?
    var briefWakes = 0                 // asleep only: how many times it woke by itself for a moment
    var briefWakeSeconds = 0.0         // asleep only: how long those moments added up to
    var startedBy: String?             // asleep only: a key for the reason ("Lid closed"), if it is one we know
    var ongoing = false                // it runs up to now
    var beginsBeforeLog = false        // the log starts in the middle of it, so it is longer than shown

    /// A session shorter than this says nothing: the battery only shows whole percent.
    static let minHours = 5.0 / 60

    var hours: Double { max(end.timeIntervalSince(start), 0) / 3600 }
    var pluggedIn: Bool { startOnAC == true || endOnAC == true }
    var onBattery: Bool { startOnAC == false && endOnAC == false }
    /// Percentage points the battery lost (negative if it gained).
    var points: Int? { (startPercent != nil && endPercent != nil) ? startPercent! - endPercent! : nil }
    /// A change of one or two points is within the rounding of both readings, so the rate is only a rough guide.
    var rough: Bool { (points ?? 0) < 3 }

    /// Points per hour, only if the whole session was on battery, both readings are known, the charge did not rise and it lasted long enough.
    var drainPerHour: Double? {
        guard onBattery, let p = points, p >= 0, hours >= Self.minHours else { return nil }
        return Double(p) / hours
    }
}

/// Several sessions of one kind added up: points lost divided by hours, which weights long sessions more than short ones.
struct DrainSummary: Equatable {
    var state: PowerState
    var sessions: Int
    var hours: Double
    var points: Int
    var briefWakes: Int
    var briefWakeSeconds: Double

    var perHour: Double { hours > 0 ? Double(points) / hours : 0 }
    /// How long a full battery would last at this rate; nil if nothing was lost.
    var hoursFromFull: Double? { perHour > 0 ? 100 / perHour : nil }
}

struct PowerPoint: Identifiable, Equatable {
    var id: Int
    var date: Date
    var percent: Int
    var onAC: Bool
    var run: Int                // consecutive points with the same power source share a run, so the chart does not join across a gap
}

/// Two neighbouring readings with a different power source: the plug or unplug happened somewhere between them, and the log does not say when.
struct PowerGap: Identifiable, Equatable {
    var id: Int                 // the index of the reading before the gap
    var from: PowerPoint
    var to: PowerPoint
}

struct PowerHistory: Equatable {
    var sessions: [PowerSession] = []   // oldest first
    var points: [PowerPoint] = []
    var awake: DrainSummary?
    var asleep: DrainSummary?
    var logRead = false                 // macOS answered (even if the log holds no sleep or wake)
    var from: Date?
    var to: Date?
}

// MARK: parsing (no hardware: tested on text)

enum PowerLogParser {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"          // "2026-10-22 13:14:25 +0300": the log states its own offset
        return f
    }()

    /// Every sleep, wake and dark wake in the text, in time order. The log is megabytes of other lines, so a line is looked at
    /// closely only if the word after the time stamp starts with S, W or D.
    static func parse(_ text: String) -> [PowerEvent] {
        var found: [(Int, PowerEvent)] = []
        for (n, slice) in text.utf8.split(separator: 10, omittingEmptySubsequences: true).enumerated() {
            guard slice.count > 28 else { continue }
            let first = slice[slice.index(slice.startIndex, offsetBy: 26)]
            guard first == 83 || first == 87 || first == 68 else { continue }          // S, W, D
            if let e = parseLine(String(decoding: slice, as: UTF8.self)) { found.append((n, e)) }
        }
        found.sort { $0.1.date != $1.1.date ? $0.1.date < $1.1.date : $0.0 < $1.0 }   // by time; same second keeps the log's own order
        return found.map { $0.1 }
    }

    /// One line, or nil if it is not a sleep, wake or dark wake that we fully understand ("Wake Requests" lines are not wakes).
    static func parseLine(_ line: String) -> PowerEvent? {
        let u = Array(line.utf8)
        guard u.count > 28, u[4] == 45, u[7] == 45, u[10] == 32, u[13] == 58, u[16] == 58, u[19] == 32, u[25] == 32,
              let date = formatter.date(from: String(decoding: u[0..<25], as: UTF8.self)) else { return nil }
        let rest = String(decoding: u[26...], as: UTF8.self)
        let word = rest.prefix { $0.isLetter }
        let kind: PowerEventKind
        let expected: String
        switch word {
        case "Sleep": kind = .sleep; expected = "Entering Sleep state"
        case "Wake": kind = .wake; expected = "Wake from"
        case "DarkWake": kind = .darkWake; expected = "DarkWake from"
        default: return nil
        }
        let message = rest.dropFirst(word.count).drop { $0 == " " || $0 == "\t" }
        guard message.hasPrefix(expected) else { return nil }
        let text = String(message)
        var reason = ""
        if kind == .sleep, let r = text.range(of: "due to '"), let end = text[r.upperBound...].firstIndex(of: "'") {
            reason = plainText(String(text[r.upperBound..<end]))
        }
        return PowerEvent(date: date, kind: kind, percent: percent(in: text), onAC: onAC(in: text), reason: reason)
    }

    /// "(Charge:67%)" -> 67. Anything not 0...100 is refused.
    static func percent(in text: String) -> Int? {
        guard let r = text.range(of: "Charge:") else { return nil }
        let digits = text[r.upperBound...].drop { $0 == " " }.prefix { $0.isNumber && $0.isASCII }
        guard let v = Int(digits), (0...100).contains(v) else { return nil }
        return v
    }

    /// "Using AC" -> true, "Using BATT" or "Using Batt" -> false, anything else -> nil.
    static func onAC(in text: String) -> Bool? {
        guard let r = text.range(of: "Using ") else { return nil }
        let word = text[r.upperBound...].prefix { $0.isLetter }.uppercased()
        return word == "AC" ? true : (word == "BATT" ? false : nil)
    }
}

// MARK: analysis (no hardware: tested on events)

enum PowerAnalysis {
    /// The reason a sleep started, in words a person uses; nil for one we do not know (it is then not shown, not guessed).
    static func startReason(_ raw: String) -> String? {
        let r = raw.lowercased()
        if r.contains("clamshell") { return trkey("Lid closed") }
        if r.contains("idle") { return trkey("Idle") }
        if r.contains("software") { return trkey("Chosen from the menu") }
        if r.contains("power button") { return trkey("Power button") }
        if r.contains("low battery") { return trkey("Battery low") }
        return nil
    }

    /// Turns events into sessions. `now` closes the session that is still going (the Mac is awake, or in a dark wake, as this runs).
    static func sessions(from events: [PowerEvent], now: (date: Date, percent: Int, onAC: Bool)?) -> [PowerSession] {
        var done: [PowerSession] = []
        var cur: PowerSession?
        var darkSince: Date?

        func close(_ s: inout PowerSession?, at e: PowerEvent) {
            guard var c = s else { return }
            c.end = max(e.date, c.start)
            c.endPercent = e.percent
            c.endOnAC = e.onAC
            done.append(c)
            s = nil
        }
        func open(_ state: PowerState, at e: PowerEvent, beforeLog: Bool = false) -> PowerSession {
            PowerSession(id: 0, state: state, start: e.date, end: e.date, startPercent: e.percent, endPercent: nil, startOnAC: e.onAC, endOnAC: nil,
                         startedBy: nil, beginsBeforeLog: beforeLog)
        }

        for e in events {
            switch e.kind {
            case .wake:
                if let d = darkSince, cur != nil { cur!.briefWakeSeconds += max(e.date.timeIntervalSince(d), 0) }   // woke fully from a dark wake
                darkSince = nil
                close(&cur, at: e)
                cur = open(.awake, at: e)
            case .sleep:
                if let d = darkSince {                                  // a dark wake going back to sleep: still the same asleep session
                    cur?.briefWakeSeconds += max(e.date.timeIntervalSince(d), 0)
                    darkSince = nil
                } else if cur?.state == .awake {
                    close(&cur, at: e)
                    cur = open(.asleep, at: e)
                    cur?.startedBy = startReason(e.reason)
                } else if cur == nil {                                  // the log begins with a sleep: how long it has lasted is unknown
                    cur = open(.asleep, at: e, beforeLog: true)
                    cur?.startedBy = startReason(e.reason)
                }                                                       // a second sleep line while asleep: nothing new
            case .darkWake:
                if cur == nil { cur = open(.asleep, at: e, beforeLog: true) }
                if cur?.state == .asleep && darkSince == nil {
                    cur!.briefWakes += 1
                    darkSince = e.date
                }
            }
        }
        if var c = cur, let n = now, n.date > c.start {
            if let d = darkSince { c.briefWakeSeconds += max(n.date.timeIntervalSince(d), 0) }
            c.end = n.date
            c.endPercent = n.percent
            c.endOnAC = n.onAC
            c.ongoing = true
            done.append(c)
        }
        return done.enumerated().map { var s = $0.element; s.id = $0.offset; return s }
    }

    /// The sessions of one kind that can be measured, added up. nil if there is none.
    static func summary(_ sessions: [PowerSession], state: PowerState) -> DrainSummary? {
        let usable = sessions.filter { $0.state == state && $0.drainPerHour != nil }
        guard !usable.isEmpty else { return nil }
        return DrainSummary(state: state, sessions: usable.count, hours: usable.reduce(0) { $0 + $1.hours },
                            points: usable.reduce(0) { $0 + ($1.points ?? 0) }, briefWakes: usable.reduce(0) { $0 + $1.briefWakes },
                            briefWakeSeconds: usable.reduce(0) { $0 + $1.briefWakeSeconds })
    }

    /// Points for the chart: every reading in the log, plus now.
    static func points(from events: [PowerEvent], now: (date: Date, percent: Int, onAC: Bool)?) -> [PowerPoint] {
        var raw: [(Date, Int, Bool)] = events.compactMap { e in e.percent.map { (e.date, $0, e.onAC ?? false) } }
        if let n = now, raw.last.map({ n.date > $0.0 }) ?? true { raw.append((n.date, n.percent, n.onAC)) }
        var run = 0
        var out: [PowerPoint] = []
        for (i, p) in raw.enumerated() {
            if let last = out.last, last.onAC != p.2 { run += 1 }
            out.append(PowerPoint(id: i, date: p.0, percent: p.1, onAC: p.2, run: run))
        }
        return out
    }

    /// Where the chart's line is cut because the power source changed. The chart joins each of these with a dashed line, so the
    /// stretch with no reading (here the Mac was awake for hours without a log line) is not mistaken for missing data or a bug.
    static func gaps(in points: [PowerPoint]) -> [PowerGap] {
        zip(points, points.dropFirst()).filter { $0.run != $1.run }.map { PowerGap(id: $0.id, from: $0, to: $1) }
    }

    /// The bottom of the chart: 0, unless the battery never went below 50%, when 50 or 75 gives the line the room instead of leaving half the chart empty.
    /// The axis labels always say which range is shown.
    static func chartFloor(_ points: [PowerPoint]) -> Int {
        guard let lowest = points.map({ $0.percent }).min(), lowest >= 50 else { return 0 }
        return lowest / 25 * 25
    }

    static func history(events: [PowerEvent], now: (date: Date, percent: Int, onAC: Bool)?, logRead: Bool) -> PowerHistory {
        let all = sessions(from: events, now: now)
        return PowerHistory(sessions: all, points: points(from: events, now: now), awake: summary(all, state: .awake), asleep: summary(all, state: .asleep),
                            logRead: logRead, from: events.first?.date, to: events.last?.date)
    }
}

// MARK: reading (the system's own log; nothing is kept)

enum PowerHistoryReader {
    /// The battery now (percentage and whether on AC), from the public power API; nil on a Mac without a battery.
    static func currentCharge() -> (percent: Int, onAC: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType, let pct = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            return (pct, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    /// Runs `pmset -g log` (about 2 seconds and 6 MB for a week), so call it from a background queue.
    static func read(now: Date = Date()) -> PowerHistory {
        let r = ToolRunner.run("/usr/bin/pmset", ["-g", "log"], timeout: 30)
        let current = currentCharge().map { (date: now, percent: $0.percent, onAC: $0.onAC) }
        return PowerAnalysis.history(events: PowerLogParser.parse(r.output), now: current, logRead: !r.timedOut && r.status == 0 && !r.output.isEmpty)
    }
}
