# BG Optimizer for Mac: UI/UX design

Visual prototype (four interactive screens, light and dark): https://claude.ai/artifact/Pc1CtBPrzjQCHiSqNTQr8f
It is private. Open it from your claude.ai account, or use Share there to give others access.

## Status: what is built (updated)

| Screen or feature | In the prototype | In the real app | Checked how |
|---|---|---|---|
| Menu-bar panel (switch, slowed list, per-job Restore, Give back) | yes | **built** | Engine calls tested with burner jobs; panel drawn to images (light, dark, 4 states); your own screenshot of the running panel |
| Observe only | yes | **built** (Settings, welcome, panel, Activity banner) | Burner test: priority untouched |
| Settings (General, Protected apps, Language) | yes | **built**; the old log tab was dropped because the Activity window replaced it | Drawn to images in both languages; opened in a throwaway copy |
| Activity window (status tiles, process table, log) | yes | **built** | Real process rows and real system readings compared with `pmset`, `sysctl`, `vm_stat`, System Information; drawn to images |
| First-launch screen | yes | **built** (shown only when no choice is saved) | Drawn to images; opened in a throwaway copy |
| Ukrainian / English | no | **built** (not in the original prototype) | See section 13 |
| Changing jobs from the table (slow down, restore, never slow this app) | no | **built** (requested after trying the Activity window) | Engine rules tested with sleeper processes and your Finder; see section 14 |
| Hide idle processes, sortable columns, Clear log | no | **built** | Clear log tested in a separate folder |
| Failed-action state, launch-at-login "needs approval" state | no | not built | |

Not yet checked by hand in the real app: clicking inside the Activity window, the welcome window's button, and the Settings controls. Not tried on any chip other than the M1.

Feasibility labels: **Possible** (can be built), **Recommended**, **Required**, **Unknown**.
Labels "tried" and "not tried" say whether I ran the underlying macOS call on this M1.

## 1. Problem

The Mac app works but its UI is a text menu plus a small Settings window. Your Windows tool (screenshot) shows a different approach: a big process table with Kill and Priority buttons. That approach does not suit the Mac app, and it carries risks (section 2). The Mac app should be glanceable, safe by default, and explain what it did.

## 2. Critique of the Windows screenshot (what to learn from it)

| Area | Observation | Principle | Consequence for the Mac design |
|---|---|---|---|
| Hierarchy | Refresh, Kill Selected and Apply Priority are the same blue | Hierarchy, error prevention | The Mac app has no Kill at all. Primary action is the on/off switch |
| Risky default | Priority dropdown is preset to "Idle" beside Apply | Error prevention | No priority picker. Slowing is automatic, rule-based and reversible |
| Evidence of the risk | `Code - Insiders` shows priority Idle in the table | Feedback | describe.md itself warns that Idle freezes interactive apps. Mac protects editors, browsers, audio |
| Signifier | "Protected" is a checkbox column, but it is not editable | Signifiers, affordance | Use a status chip with an icon and text (Protected), not a checkbox |
| Density | Table uses about half the width; the rest is empty; no "what is the app doing" column | Proportion, figure/ground | Activity table has a Status and a Details column, sized to its content |
| Empty state | Activity Log is a blank box | Feedback | Every empty area says what it means ("Nothing slowed down") |
| Contrast and targets | Grey hint text on near-black and very small tabs look low-contrast and small | Accessibility | Not measured. Mac design is built to 4.5:1 text and 24 px minimum targets; measure the Windows UI before trusting this |
| Consistency | Window says "every 2s"; describe.md says 5 s. Screenshot has 3 tabs; describe.md lists 6 or more | Consistency | Fix describe.md or the app. Mac app uses 5 s everywhere |
| Context | Memory shows 16.3 / 31.1 GB, so this is a PC, not the 16 GB M1 | Fact check | Nothing to port directly |

## 3. Objectives, users, requirements

- **User:** one person with a 16 GB M1 MacBook who runs heavy background jobs (builds, encodes, local AI) and wants a smooth foreground. Not a power user of Activity Monitor. Assumption: stated by you earlier, not researched.
- **Functional (Required):** on/off switch; see what is slowed; give it back; set how sensitive it is; protect apps; see why something was or was not slowed; launch at login.
- **Experiential:** it should be invisible most of the time, and reassuring when you look (nothing is killed, everything is reversible, the Mac is not hot).
- **Non-goals:** killing processes, per-process priority picking, RAM trimming, services/registry tweaks, cleanup tools.

## 4. Recommendation

Three options were compared:

| Option | For | Against |
|---|---|---|
| A. Text menu + Settings (today) | Smallest; fully native | No room for status or explanation; list of slowed jobs is plain text |
| **B. Panel + Settings + Activity window (recommended)** | Glance first, detail on demand; matches how the app is used | Three surfaces to build and test |
| C. One big window like the Windows tool | Everything in one place | Wrong default for a background tool; invites the risky per-process actions |

## 5. Screens (all in the prototype)

1. **Menu-bar panel.** Header with status line and the On/Off switch (label plus knob position, not color only). Three states: Active (list of slowed jobs with a "Low priority" chip, CPU and duration, per-job Restore, and "Give everything back now"), Watching (nothing slowed, calm message), Off (paused message). Footer: Settings, Activity, Quit. Menu-bar icon shows the count of slowed jobs.
2. **Settings.** Tabs General and Protected apps. General: Optimize, Open at login, Observe only, Busy threshold slider (20 to 95% of one core), duration picker, and a live plain-language sentence that restates the rule. Protected apps: your list (add, remove, choose an app) and the built-in protections shown as read-only locked items.
3. **Activity.** Header tiles for CPU load, memory pressure and thermal state (reassurance that the Mac is not being pushed). Process table with status chips Slowed, Watching, Left alone, Protected (icon plus text), filter field, legend. Log tab with the real log format.
4. **First launch.** What it does in three promises, then a choice: Observe only (recommended) or Start optimizing now, plus Open at login.

## 6. Design system (own, no brand system was attached)

- **Why native:** it is a system utility; platform conventions lower the learning cost. The prototype approximates macOS; the real app should use system semantic colors, not these hex values.
- **Type:** system font. 11 caption (uppercase labels), 12 secondary, 13 body, 15 panel title, 22 headline.
- **Spacing:** 4-point steps (4, 8, 12, 14, 16, 22). Radius 7 controls, 10 cards, 12 windows.
- **Targets:** controls 28 px high, rows 32 px, main button 36 px. These are above the 24 px minimum in WCAG 2.2 (web-qa-checklists.md); they are smaller than 44 px touch targets because this is a pointer app.
- **Color (light / dark):** surface #FFFFFF / #2C2C2E, text #1D1D1F / #F5F5F7, secondary text #5B5B62 / #A9A9B2, accent #0A7480 / #4CC9D6 (teal from the app icon). Status chips: Slowed amber, Protected indigo, neutral grey, calm green. Every status also has an icon and a word, so none depends on color. Contrast of the main pairs was estimated by hand (all above 4.5:1), not measured with a tool.
- **Open question:** use the teal accent everywhere, or follow the user's system accent color?

## 7. What each new thing needs from the engine

| Feature | Label | Notes |
|---|---|---|
| Panel instead of text menu (popover) | Possible, Recommended | The text menu stays as a fallback |
| Per-job Restore | Possible | Add a `release(pid)` next to the existing release-all |
| Observe only | Possible | The engine already has a dry-run mode; it is only reachable from the command line today |
| Activity table | Possible | Engine must publish each 5 s sample (name, CPU, status, reason); the data already exists inside the sampling loop |
| Thermal state | Built, tried | Public `ProcessInfo.thermalState`; reads "Nominal" on this Mac |
| Memory pressure, memory in use, overall CPU load | Built, tried | `kern.memorystatus_vm_pressure_level` and the Mach host statistics; memory in use matches `vm_stat` |
| Battery (charge, time left, Low Power Mode, health) | Built, tried | Live values from the public power API; health from `system_profiler`, the same source as System Information (the registry's own numbers gave 84% where System Information says 85%) |
| Storage | Built, tried | Counts space macOS can reclaim, like Finder, so a little higher than `df` |
| First-launch flow | Built | One stored flag, `didOnboard`; shown only if no choice was ever saved |
| Build with the current toolchain | Required | Only the command-line tools are installed, so SwiftUI `@State` and other macro-based features do not compile. Use `ObservableObject` as the Settings window does |

## 8. Edge cases not yet drawn

(Done since: the observe-only panel, the 8-job limit with "and N more", long names truncated with the full name on hover, Ukrainian-length text.) Still open: a failed action ("Could not slow X", status Failed with a reason); Launch at login waiting for approval in System Settings; more than 8 slowed jobs (show 8 then "and N more in Activity"); very long process names (truncate with the full name on hover); menu-bar icon hidden on a crowded notch menu bar (every action must also be reachable from the Settings window); Reduce Motion and Reduce Transparency; right-to-left and German-length text.

## 9. Accessibility (from web-qa-checklists.md, adapted to a native app)

Real buttons, labels and a table with a caption were used in the prototype. For the app: every control reachable with Full Keyboard Access; `⌘,` Settings, `⌘Y` Activity, Esc closes the panel; the menu-bar item reads as "BG Optimizer, on, 2 jobs slowed"; switches announce on/off; tabs announce selected; light, dark and Increase Contrast checked.

## 10. Security and privacy (from security-checklist.md)

No network access, no privileged helper, no special privacy permission is needed (it reads the process list of your own user). The log and the Activity table show names of your own running apps, kept on this Mac only. Check item 11 (privacy permissions) stays "none requested", and item 5 (persistence): the login item is created only when you switch it on, and the app logs that.

## 11. Validation plan

The app has no HTTP API, so api-test-cases.md does not apply. Its table style is reused for UI cases:

| ID | Pri | Case | Steps | Expected |
|---|---|---|---|---|
| UI-01 | H | Switch off releases everything | Slow a job, switch Off | Job back to priority 31; panel shows Paused |
| UI-02 | H | Per-job Restore | Slow two jobs, Restore one | Only that one returns to normal |
| UI-03 | H | Observe only changes nothing | Turn on Observe only with a busy job | Activity shows it, priority unchanged |
| UI-04 | H | Protected list wins | Add the busy app to Protected apps | It is never slowed |
| UI-05 | H | Foreground release | Slow a job, switch to it | Returns to normal within 5 s |
| UI-06 | M | Settings apply live | Move the slider while a job runs | New threshold used on the next sample; sentence updates |
| UI-07 | M | Keyboard only | Operate every screen without a mouse | All controls reachable, focus visible |
| UI-08 | M | VoiceOver | Read the panel and the Activity table | Names, states and rows are announced |
| UI-09 | M | Dark and light, Increase Contrast | Switch each | No unreadable text |
| UI-10 | M | Crowded menu bar | Fill the menu bar on a notched Mac | Settings is still reachable another way |
| UI-11 | L | Long names and German text | Use a 60-character process name | Truncated with full name on hover; no overlap |

| UI-12 | H | Switch language live | Settings > Language > Українська | Panel, Settings, Activity and window titles change at once, no restart; the choice survives a relaunch |
| UI-13 | H | Old settings survive an update | Start the new version with settings saved by the old one | Protected apps, threshold and Observe only are kept (checked in a test with your saved settings) |
| UI-14 | M | Ukrainian plurals | 1, 2, 5, 11, 21 slowed jobs | 1 завдання, 2 завдання, 5 завдань, 11 завдань, 21 завдання (checked in a test) |
| UI-15 | M | Ukrainian layout | Every screen in Ukrainian, light and dark | No overlap; long text wraps or truncates with a hover tooltip (checked on images) |

Then run the qa-reviewer agent on the finished SwiftUI code.

## 12. Open questions

Who else will use it? Teal accent or system accent? (The built app uses the system accent color; the teal appears only in the app icon.) Should the panel also carry an Open at login switch, or only Settings and the welcome screen? Is a native speaker available to review the Ukrainian wording (section 13)?

## 13. Languages: English and Ukrainian

- **Choice:** Settings > Language: System default, English, Українська. It also appears on the welcome screen. It switches live, with no restart, and is remembered. "System default" follows your Mac's language list; on this Mac that list is English, then Ukrainian, so "System default" shows English.
- **How:** every visible string goes through one lookup (`tr`). Texts live in `Resources/en.lproj/App.strings` and `Resources/uk.lproj/App.strings`. A missing translation shows the English text, never a blank. The table is named "App", not the system default "Localizable", so macOS cannot translate pieces of the interface behind the app's back.
- **Plurals:** Ukrainian has three forms (1 завдання, 2 завдання, 5 завдань; 21 завдання), so phrases that depend on a number have their own forms. Durations that follow "протягом" use the genitive case (протягом 1 хвилини, 5 хвилин).
- **Dates and numbers** follow the chosen language ("4 хвилини тому", "9,8 ГБ").
- **Stays English on purpose:** the log file and the lines of the Log tab (they are for diagnosing and sharing), the app name, and dialogs that macOS itself draws (such as the Choose app panel), which follow the system language.
- **Safety net:** `python3 tools/check_strings.py` fails the build if a key is missing, a placeholder (%d, %@) differs between English and Ukrainian, or a translation is stale.
- **Honest limit:** the Ukrainian was written by an AI assistant. It was checked for grammar rules and layout, but it needs a review by a native speaker, especially "Не чіпаю" (left alone), "Сповільнив би" (would slow) and "ЦП" (CPU).

## 14. Changing jobs yourself (added after you tried the Activity window)

**What you asked:** show more processes and let you change them, if it does not break security.

**Why this changes an earlier decision.** Section 2 criticized the Windows tool for a priority picker next to Kill, and the first design had no per-process control at all. Having used the real window, you wanted control. The compromise is to give control without the two dangerous things in that screenshot: there is no Kill and no priority picker. Only reversible actions exist.

| Action | Who can use it | Guard |
|---|---|---|
| Slow down now | Your own jobs that are not protected | Hard-refused: system, security tools, local AI, this app, anything on your protected list, the app in front. Confirmation first (default Cancel): browsers, calls, media, editors, anything keeping the Mac awake |
| Restore normal priority | A job that is slowed | None needed; it only undoes |
| Never slow "app" / Remove from the list | Any job not already hard-protected | Applies to the app name, so all processes of that app; a slowed one is released at once |

**Rules the engine enforces (not just the buttons):** the process must still be the same one (PID plus start time); the decision is made again from the real path and the current front app; refused while the app is off or in Observe only; everything is logged, including refusals; a manual slow-down is released when you restore it, bring its app to the front, it exits, or the app quits or is switched off, but not just for being quiet.

**Wording fixed after your review of the Ukrainian:** the status "Не чіпаю" and the detail "Браузер, не чіпаю" were unclear. They are now "Пропущено" and "Браузер, не сповільнюється" (English: "Skipped" and "Browser, never slowed"). The legend explains the difference between Skipped (never slowed automatically, but you may slow it after a warning) and Protected (cannot be slowed, even by you).

**Open questions:** should a job you slow by hand be remembered after the app restarts (today it is released on quit)? Should "Never slow this app" cover the whole app (today) or only the one process? Should processes be grouped by app (today every helper is its own row)?

## 15. Startup items (added after you asked about apps that start with the laptop)

**What macOS allows.** An ordinary app can switch only agents in the user's own `~/Library/LaunchAgents` (`launchctl disable gui/<uid>/<label>`, no password, survives restarts). System-wide agents and daemons need an administrator, and login-item apps are managed only in System Settings. The app does not ask for a password or install a privileged helper, because that would add a much larger security risk than the feature is worth.

**Design.** A third tab, Startup, next to Processes and Log: every item with its start trigger, whether it is running, whether it is on, and one of three controls: a switch (your own agents), "Settings…" (everything else), or a lock (security tools, macOS items, this app). Switching off means "do not start at the next login", never "stop it now", so the app's promise that it never kills anything still holds.

**On this Mac (checked):** 39 items listed, 4 can be switched here (GoogleUpdater, ChatGPT Atlas updater, CleanMyMac updater, Ollama's Homebrew agent). Two Google files in your folder are empty and start nothing. Several items you or other apps had switched off in System Settings (Grammarly, Steam) show as Off with a Settings button.

**Not built, on purpose:** stopping an item that is running now; deleting files; changing system-wide items (needs an administrator).
**Not verified:** that a switched-off agent really does not start after the next login (needs a logout; the setting itself is read back from launchd), and the System Settings button (it opens the Login Items pane).
