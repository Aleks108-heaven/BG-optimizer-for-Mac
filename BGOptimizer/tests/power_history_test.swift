// Battery history (read only): parsing the lines of macOS's own power log, turning sleeps and wakes into sessions, the drain figures,
// hostile input, and a real read whose counts are checked against a second, independent way of counting. The real read must also pass
// on a Mac without a battery or with an empty log (a virtual machine): it checks consistency, not presence.
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  pass" : "  FAIL", what); if !ok { failures += 1 } }
func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

// --- one line at a time, in the shapes macOS writes ----------------------------------------------------------------------------------
let sleepLine = "2026-10-22 12:47:52 +0300 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:48%) 610 secs  "
let wakeLine = "2026-10-22 13:14:25 +0300 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty/HID Activity Using BATT (Charge:48%)           "
let darkLine = "2026-10-22 12:58:02 +0300 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to NUB.SPMI0Sw3IRQ nub-spmi.0x02 rtc/Maintenance Using BATT (Charge:48%) 10 secs   "
let s = PowerLogParser.parseLine(sleepLine), w = PowerLogParser.parseLine(wakeLine), d = PowerLogParser.parseLine(darkLine)
check(s?.kind == .sleep && s?.percent == 48 && s?.onAC == false && s?.reason == "Clamshell Sleep" && s?.date == iso("2026-10-22T12:47:52+03:00"), "a Sleep line: kind, 48%, on battery, the reason, the time")
check(w?.kind == .wake && w?.percent == 48 && w?.onAC == false && w?.reason == "" && w?.date == iso("2026-10-22T13:14:25+03:00"), "a Wake line")
check(d?.kind == .darkWake && d?.percent == 48 && d?.date == iso("2026-10-22T12:58:02+03:00"), "a DarkWake line")
check(PowerLogParser.parseLine("2026-10-22 13:14:25 +0300 Wake Requests       \t[process=dasd request=SleepService deltaSecs=905 wakeAt=2026-10-22 13:15:40]") == nil, "'Wake Requests' is not a wake")
check(PowerLogParser.parseLine("2026-10-22 13:14:25 +0300 Assertions          \tSummary- [System: DeclUser kDisp] Using Batt(Charge: 86)") == nil, "an Assertions line is ignored")
check(PowerLogParser.parseLine("2026-10-22 13:14:25 +0300 WakeDetails         \tDriverReason:NUB.SPMI0Sw3IRQ") == nil && PowerLogParser.parseLine("2026-10-22 13:14:25 +0300 Sleepy              \tEntering Sleep state") == nil, "a longer word that starts with Wake or Sleep is ignored")
check(PowerLogParser.parseLine("2026-10-22 13:14:25 +0300 Sleep               \tSomething else entirely Using Batt (Charge:48%)") == nil, "a Sleep line with a message we do not know is ignored, not guessed")
check(PowerLogParser.parseLine("") == nil && PowerLogParser.parseLine("Time stamp                Domain") == nil && PowerLogParser.parseLine("PM ASL data store: /var/log/powermanagement") == nil, "empty and header lines")
check(PowerLogParser.parseLine("2026-13-45 99:99:99 +0300 Sleep               \tEntering Sleep state Using Batt (Charge:48%)") == nil, "an impossible date is refused")
check(PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state Using AC (Charge:100%) 1 secs")?.onAC == true && PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state Using AC (Charge:100%) 1 secs")?.percent == 100, "Using AC, 100%")
check(PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep Entering Sleep state due to 'Idle Sleep' Using BATT (Charge:9%)")?.percent == 9, "no tab, one digit (the spacing is not relied on)")
check(PowerLogParser.parseLine("2026-10-22 12:47:52 -0700 Sleep \tEntering Sleep state Using BATT (Charge:50%)")?.date == iso("2026-10-22T12:47:52-07:00"), "another time-zone offset is honoured")
check(PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state")?.percent == nil && PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state")?.onAC == nil, "no charge and no source on the line: both unknown")
check(PowerLogParser.percent(in: "Using BATT (Charge:101%)") == nil && PowerLogParser.percent(in: "(Charge:)") == nil && PowerLogParser.percent(in: "(Charge:-5%)") == nil && PowerLogParser.percent(in: "(Charge:0%)") == 0, "percent: over 100, empty, negative refused; 0 is real")
check(PowerLogParser.percent(in: "(Charge:99999999999999999999999%)") == nil, "percent: a number too big for an integer is refused, not a crash")
check(PowerLogParser.percent(in: "(Charge:٣٤%)") == nil, "percent: non-ASCII digits are refused")
check(PowerLogParser.onAC(in: "Using Wireless (Charge:5%)") == nil && PowerLogParser.onAC(in: "Using ac") == true && PowerLogParser.onAC(in: "Using batt") == false, "source: unknown word, any letter case")
let rlo = PowerLogParser.parseLine("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state due to 'Idle\u{202E}Sleep\n':TCP Using Batt (Charge:5%)")
check(rlo?.reason.contains("\u{202E}") == false && rlo?.reason.contains("\n") == false, "a reason with a direction override or a newline is cleaned")

// --- many lines: order, other lines skipped ------------------------------------------------------------------------------------------
let text = [wakeLine, "garbage", darkLine, "", sleepLine, "2026-10-22 12:47:52 +0300 Wake Requests \t[x]"].joined(separator: "\n")
let parsed = PowerLogParser.parse(text)
check(parsed.map { $0.kind } == [.sleep, .darkWake, .wake], "three events out of six lines, put in time order (the log's order was shuffled)")
let tie = [
    "2026-10-22 11:34:45 +0300 Sleep \tEntering Sleep state due to 'Idle Sleep' Using BATT (Charge:55%)",
    "2026-10-22 11:34:45 +0300 DarkWake \tDarkWake from Deep Idle [CDNP] : due to x Using BATT (Charge:55%)",
    "2026-10-22 11:34:45 +0300 Sleep \tEntering Sleep state due to 'Idle Sleep' Using BATT (Charge:55%)"].joined(separator: "\n")
check(PowerLogParser.parse(tie).map { $0.kind } == [.sleep, .darkWake, .sleep], "events in the same second keep the log's own order")
check(PowerLogParser.parse("").isEmpty && PowerLogParser.parse("\n\n\n").isEmpty, "empty text")

// --- sessions, from synthetic events -------------------------------------------------------------------------------------------------
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }
func ev(_ h: Double, _ k: PowerEventKind, _ pct: Int?, ac: Bool? = false, _ reason: String = "") -> PowerEvent { PowerEvent(date: at(h), kind: k, percent: pct, onAC: ac, reason: reason) }
func now(_ h: Double, _ pct: Int, ac: Bool = false) -> (date: Date, percent: Int, onAC: Bool) { (at(h), pct, ac) }

let a = PowerAnalysis.sessions(from: [
    ev(0, .wake, 80), ev(2, .sleep, 70, "Clamshell Sleep"), ev(3, .darkWake, 70), ev(3 + 4.0 / 3600, .sleep, 70, "Sleep Service Back to Sleep"), ev(10, .wake, 68),
], now: now(14, 60))
check(a.count == 3 && a.map { $0.state } == [.awake, .asleep, .awake], "wake, sleep, wake: awake, asleep, awake (the last one still going)")
check(a[0].hours == 2 && a[0].points == 10 && a[0].drainPerHour == 5, "awake 2 h, 80% to 70%: 5 points an hour")
check(a[1].hours == 8 && a[1].points == 2 && a[1].drainPerHour == 0.25 && a[1].startedBy == "Lid closed", "asleep 8 h, 70% to 68%: 0.25 an hour, started by the lid")
check(a[1].briefWakes == 1 && abs(a[1].briefWakeSeconds - 4) < 0.001, "the dark wake inside the sleep is counted, 4 seconds, and is not a new session")
check(a[2].ongoing && a[2].hours == 4 && a[2].points == 8 && a[2].drainPerHour == 2, "the session in progress ends now: 68% to 60% over 4 h")
check(!a[0].ongoing && !a[1].ongoing && a.enumerated().allSatisfy { $0.element.id == $0.offset }, "only the last is ongoing; ids run 0, 1, 2")
let sumA = PowerAnalysis.summary(a, state: .awake), sumS = PowerAnalysis.summary(a, state: .asleep)
check(sumA?.sessions == 2 && sumA?.hours == 6 && sumA?.points == 18 && sumA?.perHour == 3, "awake summary: 18 points over 6 h = 3 an hour (weighted; the plain average of 5 and 2 would be 3.5)")
check(sumS?.perHour == 0.25 && sumS?.hoursFromFull == 400 && sumS?.briefWakes == 1, "asleep summary: 0.25 an hour, a full battery would last 400 h")
check(PowerAnalysis.summary(a, state: .awake)?.hoursFromFull == 100.0 / 3, "awake: a full battery would last 33.3 h")

// a long chain of dark wakes is ONE asleep session
var chain: [PowerEvent] = [ev(0, .wake, 90), ev(1, .sleep, 85, "Clamshell Sleep")]
for i in 0..<100 { let h = 1.0 + Double(i) * 0.25 + 0.2; chain.append(ev(h, .darkWake, 85)); chain.append(ev(h + 5.0 / 3600, .sleep, 85, "Maintenance Sleep")) }
chain.append(ev(30, .wake, 84))
let c = PowerAnalysis.sessions(from: chain, now: nil)
check(c.count == 2 && c[1].state == .asleep && c[1].briefWakes == 100 && abs(c[1].briefWakeSeconds - 500) < 0.01, "100 dark wakes of 5 s inside one sleep: one session, 100 brief wakes, 500 s")
check(c[1].points == 1 && c[1].rough, "a 1-point change is flagged as rough")

// where the log starts
let startDark = PowerAnalysis.sessions(from: [ev(0, .darkWake, 86), ev(0.001, .sleep, 86, "Sleep Service Back to Sleep"), ev(100, .wake, 70)], now: nil)
check(startDark.count == 1 && startDark[0].state == .asleep && startDark[0].beginsBeforeLog && startDark[0].briefWakes == 1 && startDark[0].points == 16, "the log begins with a dark wake: an asleep session that begins before the log, 86% to 70%")
let startSleep = PowerAnalysis.sessions(from: [ev(0, .sleep, 86, "Maintenance Sleep"), ev(50, .wake, 80)], now: nil)
check(startSleep.count == 1 && startSleep[0].beginsBeforeLog && startSleep[0].startedBy == nil, "the log begins with a sleep line: asleep from there; an unknown reason is not shown")
check(PowerAnalysis.sessions(from: [ev(0, .wake, 80)], now: nil).isEmpty, "one wake and no 'now': the unfinished session is dropped, nothing invented")
check(PowerAnalysis.sessions(from: [], now: now(1, 50)).isEmpty, "no events at all: no sessions")

// what is excluded from the drain figures
let plugged = PowerAnalysis.sessions(from: [ev(0, .wake, 50, ac: true), ev(2, .sleep, 60, ac: true), ev(4, .wake, 60, ac: true)], now: nil)
check(plugged.allSatisfy { $0.pluggedIn && $0.drainPerHour == nil } && PowerAnalysis.summary(plugged, state: .awake) == nil, "on AC: no drain figure, not in the summary")
let halfPlugged = PowerAnalysis.sessions(from: [ev(0, .wake, 50, ac: false), ev(2, .sleep, 40, ac: true)], now: nil)
check(halfPlugged[0].pluggedIn && halfPlugged[0].drainPerHour == nil, "plugged in by the end of the session: not counted as drain")
let rising = PowerAnalysis.sessions(from: [ev(0, .wake, 50), ev(2, .sleep, 55)], now: nil)
check(rising[0].points == -5 && rising[0].drainPerHour == nil, "the charge rose while on battery at both ends: no drain figure")
let shortOne = PowerAnalysis.sessions(from: [ev(0, .wake, 50), ev(0.05, .sleep, 49)], now: nil)
check(shortOne[0].drainPerHour == nil && PowerAnalysis.summary(shortOne, state: .awake) == nil, "3 minutes: too short to say anything")
let unknownCharge = PowerAnalysis.sessions(from: [ev(0, .wake, nil), ev(2, .sleep, nil)], now: nil)
check(unknownCharge[0].points == nil && unknownCharge[0].drainPerHour == nil, "no percentage on the lines: no figure")
let unknownSource = PowerAnalysis.sessions(from: [ev(0, .wake, 50, ac: nil), ev(2, .sleep, 40, ac: nil)], now: nil)
check(unknownSource[0].drainPerHour == nil, "the source (battery or AC) not stated: not assumed to be battery")
let flat = PowerAnalysis.sessions(from: [ev(0, .sleep, 60), ev(10, .wake, 60)], now: nil)
check(flat[0].drainPerHour == 0 && PowerAnalysis.summary(flat, state: .asleep)?.hoursFromFull == nil, "no loss at all: 0 an hour and no 'would last' figure (not infinity)")

// odd sequences
let odd = PowerAnalysis.sessions(from: [ev(0, .wake, 80), ev(1, .darkWake, 78), ev(2, .sleep, 76, "Idle Sleep"), ev(2, .sleep, 76, "Idle Sleep"), ev(3, .wake, 75)], now: nil)
check(odd.count == 2 && odd[0].state == .awake && odd[0].hours == 2 && odd[1].state == .asleep && odd[1].hours == 1, "a dark wake while awake is ignored; a repeated sleep line changes nothing")
let fromDark = PowerAnalysis.sessions(from: [ev(0, .sleep, 80, "Idle Sleep"), ev(1, .darkWake, 80), ev(1.5, .wake, 79)], now: nil)
check(fromDark[0].briefWakes == 1 && abs(fromDark[0].briefWakeSeconds - 1800) < 0.01 && fromDark.count == 1 && fromDark[0].hours == 1.5, "waking fully out of a dark wake: the dark time is counted, the sleep ends at the wake (the awake session after it is unfinished, so not shown)")
let nowDark = PowerAnalysis.sessions(from: [ev(0, .wake, 80), ev(1, .sleep, 79, "Clamshell Sleep"), ev(2, .darkWake, 79)], now: now(2.01, 79))
check(nowDark.last?.state == .asleep && nowDark.last?.ongoing == true && abs((nowDark.last?.briefWakeSeconds ?? 0) - 36) < 0.01, "'now' falls inside a dark wake: the asleep session is still going, 36 s of it awake")
check(PowerAnalysis.sessions(from: [ev(0, .wake, 80), ev(5, .sleep, 70)], now: now(2, 60)).count == 1, "a 'now' earlier than the last session's start adds nothing")
check(PowerAnalysis.sessions(from: [ev(5, .wake, 80), ev(1, .sleep, 70)], now: nil).allSatisfy { $0.hours >= 0 }, "events out of order never give a negative length")

// reasons
func r(_ x: String) -> String? { PowerAnalysis.startReason(x) }
check(r("Clamshell Sleep") == "Lid closed" && r("Idle Sleep") == "Idle" && r("Software Sleep") == "Chosen from the menu" && r("Power Button Sleep") == "Power button" && r("Low Battery Sleep") == "Battery low", "reasons: lid, idle, menu, power button, low battery")
check(r("Maintenance Sleep") == nil && r("Sleep Service Back to Sleep") == nil && r("") == nil && r("pid 123 weird") == nil, "reasons: dark-wake returns and unknown ones give nothing")

// the chart's points
let pts = PowerAnalysis.points(from: [ev(0, .wake, 80), ev(1, .sleep, 78), ev(2, .wake, 78, ac: true), ev(3, .sleep, 90, ac: true), ev(4, .wake, 90, ac: false), ev(5, .sleep, nil)], now: now(6, 70))
check(pts.map { $0.percent } == [80, 78, 78, 90, 90, 70], "chart: every reading, the line without a percentage skipped, now added")
check(pts.map { $0.run } == [0, 0, 1, 1, 2, 2], "chart: a new run starts whenever the power source changes (no line across a plug-in)")
let gp = PowerAnalysis.gaps(in: pts)
check(gp.count == 2 && gp[0].from.percent == 78 && gp[0].to.percent == 78 && gp[1].from.percent == 90 && gp[1].to.percent == 90 && gp[0].id != gp[1].id, "chart: one gap per power-source change, joining the last reading before it to the first after (a plug-in 4 h later is dashed, not blank)")
check(PowerAnalysis.gaps(in: []).isEmpty && PowerAnalysis.gaps(in: Array(pts[0..<2])).isEmpty, "chart: no gap without a change of source")
func pp(_ v: Int...) -> [PowerPoint] { v.enumerated().map { PowerPoint(id: $0.offset, date: at(Double($0.offset)), percent: $0.element, onAC: false, run: 0) } }
check(PowerAnalysis.chartFloor(pp(48, 90)) == 0 && PowerAnalysis.chartFloor(pp(50, 90)) == 50 && PowerAnalysis.chartFloor(pp(74, 100)) == 50 && PowerAnalysis.chartFloor(pp(75, 100)) == 75 && PowerAnalysis.chartFloor(pp(0, 100)) == 0 && PowerAnalysis.chartFloor([]) == 0, "chart: the bottom is 0 unless the battery stayed at 50% or more, then 50 or 75")
check(PowerAnalysis.points(from: [ev(0, .wake, 80)], now: nil).count == 1 && PowerAnalysis.points(from: [], now: nil).isEmpty, "chart: one point, and none")
check(PowerAnalysis.points(from: [ev(5, .wake, 80)], now: now(1, 70)).count == 1, "chart: a 'now' before the last reading is not added")

// --- the whole thing, from text to history ---------------------------------------------------------------------------------------------
let tz = " +0300 "
let log = """
PM ASL data store: /var/log/powermanagement
2026-10-15 16:41:26\(tz)DarkWake            \tDarkWake from Deep Idle [CDNP] : due to x Using BATT (Charge:86%) 2 secs
2026-10-15 16:41:28\(tz)Sleep               \tEntering Sleep state due to 'Sleep Service Back to Sleep':TCPKeepAlive=inactive Using Batt (Charge:86%) 718 secs
2026-10-22 10:46:39\(tz)Wake                \tWake from Deep Idle [CDNVA] : due to lid Using BATT (Charge:67%)
2026-10-22 11:34:45\(tz)Sleep               \tEntering Sleep state due to 'Idle Sleep':TCPKeepAlive=active Using Batt (Charge:55%) 0 secs
2026-10-22 11:50:05\(tz)Wake                \tWake from Deep Idle [CDNVA] : due to lid Using BATT (Charge:55%)
"""
let h = PowerAnalysis.history(events: PowerLogParser.parse(log), now: (iso("2026-10-22T12:50:05+03:00"), 48, false), logRead: true)
check(h.sessions.map { $0.state } == [.asleep, .awake, .asleep, .awake] && h.logRead && h.from == iso("2026-10-15T16:41:26+03:00") && h.to == iso("2026-10-22T11:50:05+03:00"), "text to history: asleep (before the log), awake, asleep, awake (now)")
check(h.asleep != nil && h.awake != nil && h.awake!.points == 19 && abs(h.awake!.hours - (Double(48 * 60 + 6) / 3600 + 1)) < 1e-9, "awake: 67 to 55 (48 min 6 s) and 55 to 48 (1 h) = 19 points over 1 h 48 min 6 s")
check(abs(h.awake!.perHour - 19 / (Double(48 * 60 + 6) / 3600 + 1)) < 1e-9 && h.asleep!.points == 19 && h.asleep!.sessions == 2, "asleep: the week-long one (86 to 67) and the 15-minute one (55 to 55)")

// --- hostile and huge input ------------------------------------------------------------------------------------------------------------
let big = String(repeating: sleepLine + "\n" + darkLine + "\n" + wakeLine + "\n", count: 30_000)
let t1 = Date(); let bigParsed = PowerLogParser.parse(big); let dt = Date().timeIntervalSince(t1)
check(bigParsed.count == 90_000, "90,000 events parsed from a 17 MB text")
check(dt < 20, String(format: "...in %.1f s (limit 20)", dt))
check(PowerLogParser.parse(String(repeating: "x", count: 2_000_000)).isEmpty, "a 2 MB line with no newline is skipped")
check(PowerLogParser.parse("2026-10-22 12:47:52 +0300 Sleep \tEntering Sleep state\u{0}\u{0}\u{0} Using BATT (Charge:5%)").count == 1, "a NUL character in a line does not stop the parse")
check(PowerAnalysis.history(events: bigParsed, now: nil, logRead: true).sessions.count > 0, "90,000 events analysed without a crash")

// --- a real read, checked a second way ------------------------------------------------------------------------------------------------
let real = ToolRunner.run("/usr/bin/pmset", ["-g", "log"], timeout: 30)
let events = PowerLogParser.parse(real.output)
let hist = PowerHistoryReader.read()
print("  info pmset exit \(real.status), \(real.output.utf8.count) bytes, \(events.count) events, \(hist.sessions.count) sessions, battery now \(PowerHistoryReader.currentCharge().map { "\($0.percent)% onAC=\($0.onAC)" } ?? "none")")
for ses in hist.sessions.suffix(6) {
    print("  info \(ses.state) \(ses.start) -> \(ses.end) \(ses.startPercent.map(String.init) ?? "?")->\(ses.endPercent.map(String.init) ?? "?") rate=\(ses.drainPerHour.map { String(format: "%.2f", $0) } ?? "-") brief=\(ses.briefWakes)\(ses.ongoing ? " ongoing" : "")")
}
if let aw = hist.awake { print(String(format: "  info awake  %.2f points/h over %.1f h (%d sessions)", aw.perHour, aw.hours, aw.sessions)) }
if let sl = hist.asleep { print(String(format: "  info asleep %.3f points/h over %.1f h (%d sessions), %d brief wakes", sl.perHour, sl.hours, sl.sessions, sl.briefWakes)) }
// a second, independent count of the same text: split on lines and look for the message each kind starts with
let lines = real.output.components(separatedBy: "\n")
let sleeps = lines.filter { $0.contains("\tEntering Sleep state") }.count
let darks = lines.filter { $0.contains("\tDarkWake from") }.count
let wakes = lines.filter { $0.contains("\tWake from") }.count
check(events.filter { $0.kind == .sleep }.count == sleeps && events.filter { $0.kind == .darkWake }.count == darks && events.filter { $0.kind == .wake }.count == wakes, "the parser finds as many sleeps (\(sleeps)), dark wakes (\(darks)) and wakes (\(wakes)) as a plain text count")
check(zip(events, events.dropFirst()).allSatisfy { $0.date <= $1.date }, "real events are in time order")
check(hist.sessions.enumerated().allSatisfy { $0.element.id == $0.offset && $0.element.end >= $0.element.start }, "real sessions: ids in order, none ends before it starts")
check(zip(hist.sessions, hist.sessions.dropFirst()).allSatisfy { $0.end <= $1.start.addingTimeInterval(1) }, "real sessions do not overlap")
check(hist.sessions.allSatisfy { ($0.startPercent ?? 0) <= 100 && ($0.endPercent ?? 0) <= 100 && $0.hours < 24 * 60 }, "real sessions: percentages in range, none longer than 60 days")
check(hist.sessions.filter { $0.state == .asleep }.allSatisfy { $0.briefWakeSeconds <= $0.hours * 3600 + 1 }, "real asleep sessions: brief wakes never add up to more than the session")
check(hist.sessions.dropLast().allSatisfy { !$0.ongoing } && (hist.sessions.last?.ongoing ?? true), "real: only the last session can be ongoing")
check(events.isEmpty || hist.logRead, "if the log has events, it counts as read")
check(hist.sessions.filter { $0.state == .asleep }.reduce(0) { $0 + $1.briefWakes } <= darks, "real: brief wakes in sessions never exceed the dark wakes in the log")
let tAgain = Date(); _ = PowerLogParser.parse(real.output); let dReal = Date().timeIntervalSince(tAgain)
check(dReal < 5, String(format: "parsing the real log takes %.2f s (limit 5)", dReal))

print(failures == 0 ? "POWER HISTORY: ALL PASSED" : "POWER HISTORY: \(failures) FAILED"); exit(failures == 0 ? 0 : 1)
