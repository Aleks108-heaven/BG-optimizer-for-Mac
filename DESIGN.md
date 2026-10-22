# BG Optimizer for Mac: UI/UX design notes

These notes record what the interface is, why it is that way, and what was and was not checked. They follow a
design-review structure (problem, users, options, specification, edge cases, accessibility, risks, validation).

## Status: what is built

| Screen or feature | In the real app | Checked how |
|---|---|---|
| Menu-bar panel (switch, slowed list, per-job Restore, Give back) | **built** | Engine calls tested with burner jobs; panel drawn to images (light, dark, 4 states); confirmed in the running app by a user |
| Observe only | **built** (Settings, welcome, panel, Activity banner) | Burner test: priority untouched |
| Settings (General, Protected apps, Language) | **built** | Drawn to images in both languages; opened in a throwaway copy |
| Activity window (status tiles, process table, log) | **built** | Real process rows and real system readings compared with `pmset`, `sysctl`, `vm_stat`, System Information; drawn to images |
| First-launch screen | **built** (shown only when no choice is saved) | Drawn to images; opened in a throwaway copy |
| English / Ukrainian | **built** | See section 13 |
| Changing jobs from the table (slow down, restore, never slow this app) | **built** | Engine rules tested with sleeper processes and a system process; see section 14 |
| Startup items | **built** | Parsers tested on fixed text; a real switch off and on read back from launchd; see section 15 |
| Hide idle processes, sortable columns, Clear log | **built** | Clear log tested in a separate folder |
| Failed-action state, launch-at-login "needs approval" state | not built | |

Not checked by hand in the real app: the Settings controls, the welcome window's button, and clicking inside the
Activity window beyond the row menu. Not tried on any chip other than the M1, or on any macOS other than 27.

Feasibility labels: **Possible** (can be built), **Recommended**, **Required**, **Unknown**. "Tried" means the
underlying macOS call was run on the development Mac.

## 1. Problem

Heavy background jobs (builds, encodes, local AI, updaters) can make the foreground feel slow on a laptop. macOS already
manages priority, but a runaway job can still get in the way. The app should be glanceable, safe by default, and explain
what it did. An earlier Windows tool took the opposite approach, a big process table with Kill and Priority buttons,
and that approach does not suit this app (section 2).

## 2. Lessons from an earlier Windows tool

| Area | Observation | Principle | Consequence for the Mac design |
|---|---|---|---|
| Hierarchy | Refresh, Kill and Apply Priority looked identical | Hierarchy, error prevention | No Kill at all. The primary action is the on/off switch |
| Risky default | The priority picker was preset to "Idle" beside Apply | Error prevention | No priority picker. Slowing is rule-based and reversible; manual control offers only reversible actions |
| Evidence of the risk | An editor showed priority Idle in the table | Feedback | Interactive apps (editors, browsers, audio) are never slowed automatically |
| Signifier | "Protected" was a checkbox column that could not be edited | Signifiers, affordance | A status chip with an icon and text, not a checkbox |
| Density | The table used about half the width and had no "what is the tool doing" column | Proportion | A Status and a Details column sized to their content |
| Empty state | The log was a blank box | Feedback | Every empty area says what it means |
| Consistency | Refresh interval and tab count in the UI differed from its documentation | Consistency | One 5-second interval everywhere |

## 3. Objectives, users, requirements

- **User:** someone on an Apple Silicon laptop who runs heavy background jobs and wants a smooth foreground; not
  necessarily a power user of Activity Monitor. (An assumption, not researched.)
- **Functional (Required):** on/off switch; see what is slowed; give it back; set how sensitive it is; protect apps; see
  why something was or was not slowed; launch at login.
- **Experiential:** invisible most of the time, and reassuring when looked at (nothing is killed, everything is
  reversible, the Mac is not hot).
- **Non-goals:** killing processes, arbitrary priority picking, RAM trimming, services/registry tweaks, cleanup tools.

## 4. Options and recommendation

| Option | For | Against |
|---|---|---|
| A. Text menu + Settings | Smallest; fully native | No room for status or explanation; the slowed list is plain text |
| **B. Panel + Settings + Activity window (chosen)** | Glance first, detail on demand; matches how the app is used | Three surfaces to build and test |
| C. One big window like the Windows tool | Everything in one place | Wrong default for a background tool; invites risky per-process actions |

## 5. Screens

1. **Menu-bar panel.** Header with status line and the On/Off switch (label plus knob position, not color only). Three
   states: Active (list of slowed jobs with a "Low priority" chip, CPU and duration, per-job Restore, and "Give
   everything back now"), Watching (nothing slowed, calm message), Off (paused message). Footer: Settings, Activity,
   Quit. The menu-bar icon shows the count of slowed jobs.
2. **Settings.** Tabs General and Protected apps. General: Optimize, Launch at login, Observe only, Language, a busy
   threshold slider (20 to 95% of one core) and a duration picker. Protected apps: the user's list (add, remove, choose an
   app) and the built-in protections as read-only locked items.
3. **Activity.** Header tiles for CPU load, memory pressure, thermal state, storage and battery (reassurance that the
   Mac is not being pushed). Tabs Processes (status chips Slowed, Watching, Would slow, Skipped, Protected, Normal with
   icon plus text, filter field, legend), Startup, and Log.
4. **First launch.** What it does in three promises, then a choice: Observe only (recommended) or Start optimizing now,
   plus Launch at login.

## 6. Design system

- **Why native:** a system utility; platform conventions lower the learning cost. The app uses system semantic colors
  and controls.
- **Type:** system font. 11 caption (uppercase labels), 12 secondary, 13 body, 15 panel title, 22 headline.
- **Spacing:** 4-point steps (4, 8, 12, 14, 16, 22). Radius 7 controls, 10 cards, 12 windows.
- **Targets:** controls 28 px high, rows 32 px, main button 36 px. These are above the 24 px minimum in WCAG 2.2
  (`web-qa-checklists.md`); they are smaller than 44 px touch targets because this is a pointer app.
- **Status colors (light / dark):** Slowed amber, Protected indigo, neutral grey, calm green, attention red-orange. Every
  status also has an icon and a word, so none depends on color. Contrast of the main pairs was estimated by hand (all
  above 4.5:1), not measured with a tool.
- **Accent:** the system accent color; the teal appears only in the app icon.

## 7. What each feature needs from the engine

| Feature | Label | Notes |
|---|---|---|
| Panel instead of text menu (popover) | Built | The text menu stays as a fallback (right-click) |
| Per-job Restore | Built | `release(pid)` next to release-all |
| Observe only | Built | The engine's dry-run mode, reachable from Settings |
| Activity table | Built | The engine publishes each 5 s sample (name, CPU, status, reason) while the window is visible |
| Thermal state | Built, tried | Public `ProcessInfo.thermalState` |
| Memory pressure, memory in use, overall CPU load | Built, tried | `kern.memorystatus_vm_pressure_level` and the Mach host statistics; memory in use matches `vm_stat` |
| Battery (charge, time left, Low Power Mode, health) | Built, tried | Live values from the public power API; health from `system_profiler`, the same source as System Information (the registry's own numbers differed by one percentage point) |
| Storage | Built, tried | Counts space macOS can reclaim, like Finder, so a little higher than `df` |
| First-launch flow | Built | One stored flag, `didOnboard`; shown only if no choice was ever saved |
| Build with only the command-line tools | Required | SwiftUI `@State` and other macro-based features need Xcode's macro plugin, so the code uses `ObservableObject` |

## 8. Edge cases

Done: the observe-only panel, the 8-job limit with "and N more", long names truncated with the full name on hover,
Ukrainian-length text, a window that can be made small. Still open: a failed-action state; launch at login waiting for
approval in System Settings; a menu-bar icon hidden on a crowded notch menu bar (every action must also be reachable
from the Settings window); Reduce Motion and Reduce Transparency; right-to-left text.

## 9. Accessibility (from `web-qa-checklists.md`, adapted to a native app)

Real buttons, labels and a table with a caption; every control reachable with Full Keyboard Access; `⌘,` Settings, `⌘Y`
Activity, Esc closes the panel; the menu-bar item reads as "BG Optimizer, on, 2 jobs slowed"; switches announce on/off;
tabs announce selected. Light, dark and Increase Contrast should be checked by hand.

## 10. Security and privacy (from `security-checklist.md`)

No network access, no privileged helper, no special privacy permission (it reads the process list of the current user).
The log and the Activity table show names of the user's own running apps, kept on the Mac only, in files readable only
by the user. The login item is created only when switched on, and the app logs that. See `SECURITY-REVIEW.md`.

## 11. Validation plan

The app has no HTTP API, so `api-test-cases.md` does not apply; its table style is reused for UI cases.

| ID | Pri | Case | Steps | Expected |
|---|---|---|---|---|
| UI-01 | H | Switch off releases everything | Slow a job, switch Off | Job back to priority 31; panel shows Paused |
| UI-02 | H | Per-job Restore | Slow two jobs, Restore one | Only that one returns to normal |
| UI-03 | H | Observe only changes nothing | Turn on Observe only with a busy job | Activity shows it, priority unchanged |
| UI-04 | H | Protected list wins | Add the busy app to Protected apps | It is never slowed |
| UI-05 | H | Foreground release | Slow a job, switch to it | Returns to normal within 5 s |
| UI-06 | M | Settings apply live | Move the slider while a job runs | New threshold used on the next sample |
| UI-07 | M | Keyboard only | Operate every screen without a mouse | All controls reachable, focus visible |
| UI-08 | M | VoiceOver | Read the panel and the Activity table | Names, states and rows are announced |
| UI-09 | M | Dark and light, Increase Contrast | Switch each | No unreadable text |
| UI-10 | M | Crowded menu bar | Fill the menu bar on a notched Mac | Settings is still reachable another way |
| UI-11 | L | Long names and German text | Use a 60-character process name | Truncated with full name on hover; no overlap |
| UI-12 | H | Switch language live | Settings > Language > Українська | Panel, Settings, Activity and window titles change at once; the choice survives a relaunch |
| UI-13 | H | Old settings survive an update | Start the new version with settings saved by the old one | Protected apps, threshold and Observe only are kept (tested) |
| UI-14 | M | Ukrainian plurals | 1, 2, 5, 11, 21 slowed jobs | 1 завдання, 2 завдання, 5 завдань, 11 завдань, 21 завдання (tested) |
| UI-15 | M | Ukrainian layout | Every screen in Ukrainian, light and dark | No overlap; long text wraps or truncates with a hover tooltip (checked on images) |

An independent review of the SwiftUI code, by someone other than its author, has not been done.

## 12. Open questions

Teal accent or system accent? (The app uses the system accent.) Should the panel also carry a Launch at login switch, or
only Settings and the welcome screen? Should a job slowed by hand be remembered after the app restarts (today it is
released on quit)? Should "Never slow this app" cover the whole app (today) or only the one process? Should processes
be grouped by app (today every helper is its own row)?

## 13. Languages: English and Ukrainian

- **Choice:** Settings > Language: System default, English, Українська. It also appears on the welcome screen. It
  switches live, with no restart, and is remembered. "System default" follows the Mac's language list.
- **How:** every visible string goes through one lookup (`tr`). Texts live in `Resources/en.lproj/App.strings` and
  `Resources/uk.lproj/App.strings`. A missing translation shows the English text, never a blank. The table is named
  "App", not the system default "Localizable", so macOS cannot translate pieces of the interface behind the app's back.
- **Plurals:** Ukrainian has three forms (1 завдання, 2 завдання, 5 завдань; 21 завдання), so phrases that depend on a
  number have their own forms. Durations that follow "протягом" use the genitive case (протягом 1 хвилини, 5 хвилин).
- **Dates and numbers** follow the chosen language ("4 хвилини тому", "9,8 ГБ").
- **Stays English on purpose:** the log file and the lines of the Log tab (they are for diagnosing and sharing), the app
  name, and dialogs that macOS itself draws (such as the Choose app panel), which follow the system language.
- **Safety net:** `python3 BGOptimizer/tools/check_strings.py` fails the build if a key is missing, a placeholder
  (%d, %@) differs between English and Ukrainian, or a translation is stale.
- **Honest limit:** the Ukrainian was written with AI assistance and checked for grammar rules and layout. A native
  speaker has reviewed part of it (the status wording was revised on that feedback); a full review is still welcome.

## 14. Changing jobs by hand

**Why this changes an earlier decision.** The first design had no per-process control, because the earlier Windows tool
showed how risky a priority picker next to Kill is. Trying the real Activity window showed that people want to see all
processes and change some of them. The compromise is control without the two dangerous things: there is no Kill and no
priority picker. Only reversible actions exist.

| Action | Who can use it | Guard |
|---|---|---|
| Slow down now | The user's own jobs that are not protected | Hard-refused: system, security tools, local AI, this app, anything on the protected list, the app in front. Confirmation first (default Cancel): browsers, calls, media, editors, anything keeping the Mac awake |
| Restore normal priority | A job that is slowed | None needed; it only undoes |
| Never slow "app" / Remove from the list | Any job not already hard-protected | Applies to the app name, so all processes of that app; a slowed one is released at once |

**Rules the engine enforces (not just the buttons):** the process must still be the same one (PID plus start time); the
decision is made again from the real path and the current front app; refused while the app is off or in Observe only;
everything is logged, including refusals; a manual slow-down is released when restored, when its app comes to the
front, when it exits, or when the app quits or is switched off, but not just for being quiet.

**Wording revised after native-speaker feedback:** the status "Не чіпаю" and the detail "Браузер, не чіпаю" were unclear.
They are now "Пропущено" and "Не сповільнюється: Браузер" (English: "Skipped" and "Never slowed: Browser"). The legend
explains the difference between Skipped (never slowed automatically, but it may be slowed by hand after a warning) and
Protected (cannot be slowed, even by hand).

## 15. Startup items

**What macOS allows.** An ordinary app can switch only agents in the user's own `~/Library/LaunchAgents`
(`launchctl disable gui/<uid>/<label>`, no password, survives restarts). System-wide agents and daemons need an
administrator, and login-item apps are managed only in System Settings. The app does not ask for a password or install a
privileged helper, because that would add a much larger security risk than the feature is worth.

**Design.** A Startup tab next to Processes and Log: every item with its start trigger, whether it is running, whether it
is on, and one of three controls: a switch (the user's own agents), "Settings…" (everything else), or a lock (security
tools, macOS items, this app). Switching off means "do not start at the next login", never "stop it now", so the app's
promise that it never kills anything still holds.

**On the development Mac:** 39 items were listed and 4 could be switched (update helpers of common apps and a local AI
tool's service agent). Two files in the user's agents folder were empty and start nothing. Items that had been switched
off in System Settings show as Off with a Settings button.

**Not built, on purpose:** stopping an item that is running now; deleting files; changing system-wide items (needs an
administrator).
**Not verified:** that a switched-off agent really does not start after the next login (needs a logout; the setting
itself is read back from launchd), and the System Settings button (it opens the Login Items pane).

## 16. Storage (caches, logs and leftovers)

**Why.** Removing an app often leaves files behind: settings, containers, caches, and registrations that show as Off or
"Unknown" in System Settings. A person may want to see them. A cleaner that deletes by guess is the opposite of this app's
promise, so this tab is built as the safe version of one.

**Design.** A Storage tab: caches, logs and Xcode build files of apps that are there, and *possible leftovers*. Each row has
Reveal in Finder and Move to Trash… (confirmation, Cancel by default). No automatic cleaning, no schedule, no "clean all".
Move to Trash keeps the promise that every change is reversible. It is disabled in Observe only mode, like changing jobs by hand.

**What counts as a possible leftover.** A name that is a reverse-DNS identifier (starts with `com.`, `org.`, `net.`, ...;
a team ID or `group.` prefix is read through), whose *maker* (the part after the prefix) matches no installed app (the
usual Applications folders, two levels deep, including helpers and extensions inside apps) and no app that macOS can find by
that exact identifier. Matching on the maker, not the whole identifier, errs on the side of showing less: a leftover of a removed
app from a maker you still have another app from is not listed. Plain names ("Mac Monitor"), file names and team-prefixed names
that are not reverse-DNS are never listed, because they do not say who owns them. Apple's own items are never listed.

**Dogfooding found these on the development Mac:** a first version listed 138 "leftovers"; most were wrong (file names such as
`default.store`, Apple groups such as `groups.com.apple.podcasts`, Microsoft Office containers, Shortcuts). The rule was
tightened to reverse-DNS only, which left 116 real vendor leftovers (TotalAV 275 MB, CleanMyMac, Avira, ESET, Malwarebytes, ...),
plus the test runs' own settings files, which the self-test now removes.

**Used by a running app.** Evaluated at scan time and again when you press the button, from the programs running at that
moment (their bundle identifiers and path names). It is a best-effort guard; the Trash is the real safety net.

**Not built, on purpose:** automatic or scheduled cleaning; permanent delete; anything in `/Library`; removing system
extensions (needs SIP off, or the vendor's uninstaller); guessing leftovers from plain folder names; Full Disk Access.
**Not verified:** the buttons clicked in the real window; moving another app's container (macOS 14+ protects those).

## 17. Drivers

**The question.** "Can drivers that are outdated and no longer used be found, and removed?" On an Apple silicon Mac a driver is
mostly a *system extension*; the old *kernel extensions* are rare, and apps leave *root helper tools* behind. Found, yes.
Removed, not by this app.

**Design.** A Drivers tab, read only: system extensions (`systemextensionsctl list`), kernel extensions in `/Library/Extensions`
and root helpers in `/Library/PrivilegedHelperTools`. Each row has a status: *Probably not in use* (switched off, and no app from
the same maker is installed), *Maker's app not found*, *Switched off*, *Waiting*, *Old type* (kernel extension), *Enabled*,
*Installed*. Most interesting first. The maker rule is the Storage tab's: a maker with any installed app is never reported as gone,
which errs toward showing less. A name that says nothing about a maker is never flagged. Apple's own items are never listed.

**"Outdated" is not decided.** That needs the maker's list of current versions, and this app never uses the network. It shows the
version, or for a helper tool the day it was installed, and says in the tab that only the maker can tell.

**Old is not unused.** On the development Mac the two Adobe helpers date from Dec 2024 and look like leftovers, but their client
(Adobe Acrobat Updater) is installed and they are in use. Age alone flags nothing.

**Why not remove them.** It needs an administrator, so the app would need a privileged helper, which is the weakness the tab looks
for. `systemextensionsctl uninstall` needs SIP off. A wrong guess can break security software. The tab names the maker's uninstaller
and leaves the decision to you.

**Not built, on purpose:** any removal; a network lookup of versions; guessing a maker from a plain name.
**Not verified:** the tab clicked in the real window; reading a real kernel extension (the development Mac has none; stand-in folders
are tested); how `systemextensionsctl gc` behaves with SIP on.

## 18. Small windows: the table keeps its room

**What was wrong.** The window can be made about 600 x 440. There, the five status tiles took about 250 of its 440 points, and on
the Startup, Drivers and Storage tabs a long explanation took more: the Drivers tab showed no table row at all, and the Processes
tab about two and a half. The toolbar also overflowed both edges. Seen in snapshots (`--snapshot-windows`, which now also draws the
small size), not guessed.

**Changes.** (1) The tiles stay only on the Processes tab when the window is tall (600 points or more); otherwise one line, or two
in a narrow window, with the same readings, the same warning symbols and the battery's time left; the longer wording is in the
tooltip. (2) Each tab's explanation is one line with **More**; the full text replaces the line instead of repeating it. (3) The tab
picker has its natural width and lines up with the content; the filter and the Hide idle switch move to a second line when there is
no room. (4) In Drivers the status column follows the name, so the verdict is seen even when the table scrolls sideways, and the
detail texts are short enough to show the maker.

**Result at 600 x 440** (sample data: 7 drivers, 9 processes): Drivers 0 to 6 of 7 rows visible, Processes about 2.5 rows to all 9 with room left, no clipped toolbar, in English and Ukrainian.
**Not checked:** VoiceOver and Full Keyboard Access on the new strip and the More button (labels are set, not heard); contrast was
not measured, the colours are the existing ones.

