# BG Optimizer for Mac

A menu-bar app for Apple Silicon Macs (written and tested on a MacBook M1). When a background job
keeps one of your user processes busy (default: over 50% of a core for one minute), it puts that
process in macOS background mode, so it runs at low priority on the efficiency cores and your
foreground work stays smooth. It never kills anything.

A slowed process goes back to normal when it comes to the foreground, when it calms down (under a quarter
of your threshold for a minute), when you pick "Give everything back now", when you switch the app off,
or when you quit.

## Install

**From the installer:** open `BGOptimizer/dist/BG-Optimizer-1.0.dmg` and drag *BG Optimizer* onto
*Applications*. The app is self-signed, not notarized (that needs a paid Apple Developer account), so on
another Mac, or after a download, macOS may refuse the first launch: right-click the app and choose Open.

**From source** (needs only the Xcode command-line tools, no Xcode):

    cd BGOptimizer
    ./build.sh --install        # build + copy to ~/Applications/BG Optimizer.app
    ./build.sh --dmg            # build + dist/BG-Optimizer-1.0.dmg

## Install on another Mac, or share it

**Requirements:** an Apple Silicon Mac (M1 or newer; the app is arm64 only, there is no Intel build) and macOS 13 or
newer. It was built for 13+, but it has only been run on macOS 27 on an M1 (the machine it was written on).

**Option 1: the installer.** Download `BG-Optimizer-1.0.dmg` from the repository's Releases page, check its SHA-256
against the one in the release notes (`shasum -a 256 BG-Optimizer-1.0.dmg`), open it and drag *BG Optimizer* onto
*Applications*. The app is self-signed, not notarized, so macOS will block the first launch of a downloaded copy.
Allow it once: try to open it, then System Settings > Privacy & Security, scroll to the message about
"BG Optimizer" and choose **Open Anyway** (it asks for your password). Or, in Terminal:
`xattr -dr com.apple.quarantine "/Applications/BG Optimizer.app"`. (On recent macOS versions the Control-click >
Open shortcut no longer works for apps like this.) I checked that macOS's policy check rejects this build; I
could not test the first launch on a second Mac.

**Option 2: build it on the new Mac (best for your own Macs).** An app you build yourself is not quarantined, so there
is no warning:

    xcode-select --install                      # once; installs the command-line tools (no full Xcode needed)
    git clone <this repository>
    cd <repository>/BGOptimizer
    ./build.sh --install                        # builds and copies the app to ~/Applications

**Without any warning for other people** the app must be signed with an Apple *Developer ID* and notarized by Apple.
That needs a paid Apple Developer Program account; the build script does not do it yet.

Your settings, protected list and the Launch at login choice are not copied between Macs: a new Mac starts with the
welcome screen. To remove the app completely: switch off Launch at login, quit it, delete
`~/Applications/BG Optimizer.app`, and delete `~/Library/Application Support/BGOptimizer`, `~/Library/Logs/BGOptimizer`
and the settings (`defaults delete com.alexxxela.bgoptimizer`).

## Use

A speedometer icon appears in the menu bar. The number next to it is how many processes are slowed.

**Click the icon** to open the panel: the on/off switch, a status line, and each slowed job with its CPU use,
how long ago it was slowed, and a **Restore** button (a job you restore is not slowed again until it calms
down or exits). Below are **Give everything back now**, Settings…, Activity… (⌘Y) and Quit.
**Right-click (or control-click)** the icon for the plain text menu, which also has Launch at login.
It is the way in if macOS hides the icon on a crowded menu bar.

**Settings window**

- *General*: on/off switch, launch at login, **Observe only** (the log shows what would be slowed; nothing
  is changed, and anything already slowed is given back), how busy (20-95% of one core) and for how long (30 s to 5 min)
  before a job is slowed, and what is slowed right now. Changes apply immediately.
- *Protected apps*: apps you never want slowed (type a name or choose an app), on top of the built-ins.
- *Language*: **System default, English or Українська** (Ukrainian). It switches at once, with no restart, and
  is remembered. The welcome screen has the same picker. "System default" follows your Mac's language list
  (the first of English or Ukrainian found). The log file and the Log tab stay in English on purpose;
  dialogs drawn by macOS itself (for example the Choose app panel) follow the system language.

**Activity window** (panel > Activity…)

- *Status tiles* about the Mac itself, refreshed every 5 seconds while the window is open: CPU load,
  memory (pressure level and GB in use), thermal state (whether macOS is throttling the chip), battery
  (charge, time left or to full, Low Power Mode, and health: condition, maximum capacity, cycle count) and
  free storage. A tile shows a warning symbol and wording, not just a color, when something needs attention.
  Battery health is read from the same source as System Information. Free storage counts space macOS can
  reclaim, like Finder does, so it is a little higher than `df`.
- *Processes*: **all of your own processes** (not system or other users'), busiest first, with CPU use and a
  status chip: Slowed, Watching, Would slow (observe only), Skipped (browsers, calls, media, editors, the app in
  front: never slowed automatically), Protected (system, security, local AI, your list: never slowed, even by
  you) or Normal, plus the reason in plain words. Click a column header to sort, filter by name, or hide idle
  processes. The engine builds these rows only while this window is open.
- *Change a job* (the **…** button at the end of a row opens a native menu at the mouse). Only these reversible actions exist:
  - **Slow down now**: puts it in macOS background mode (low priority, efficiency cores). For browsers,
    calls, media apps, editors and anything keeping the Mac awake you get a warning first (the default
    button is Cancel).
  - **Restore normal priority** for a job that is slowed.
  - **Never slow “app”**: adds the app to your protected list (all of its processes). **Remove from the
    protected list** undoes it. If the job was slowed, it goes back to normal at once.
  - A job that cannot be changed shows why in the menu (for example "System process", "You are using it").
  A job you slowed yourself stays slowed until you restore it, bring its app to the front, or it exits (it is
  not released just for being quiet). A banner above the table confirms or explains each action.
  There is no kill and no way to raise priority.
- *Startup*: everything that starts by itself when you log in or the Mac boots, apart from macOS's own items:
  agents and daemons from your own and the system Library, and apps registered as login items. Each row shows
  what it is, when it starts (at login, kept running, on a schedule, on demand), whether it is running now, and
  whether it is on. **Only your own agents (in ~/Library/LaunchAgents) have a switch**, because macOS lets an
  ordinary app change only those, with no password: switching one off tells launchd not to start it at the next
  login (`launchctl disable`) and it can be switched back on. It never stops what is running and never deletes
  anything. System-wide items and login-item apps show their state and a **Settings…** button that opens
  System Settings, because changing them needs an administrator. Security tools, macOS items and this app are
  locked. The list takes a few seconds to read and is read only when you open the tab or press Refresh.
- *Log*: the recent activity log, with **Clear log…** (asks first). The full log is
  `~/Library/Logs/BGOptimizer/actions.log` (rolls over at 1 MB).

**First launch**: on the very first start (no saved choice yet) a welcome window explains the safety rules
and asks how to start: *Observe only* (recommended) or *Start optimizing now*, plus Open at login, which is
off unless you tick it. Nothing is applied until you press Get started; closing the window leaves everything
off. `--first-run` shows it again for testing.

It starts OFF; your choices are remembered. Launch at login may need your approval in
System Settings > Login Items. Keep the app in ~/Applications; login items remember the location.
Command line: `BGOptimizer --login on|off|status`.

While an Activity, Settings or welcome window is open the app has a Dock icon and a normal menu bar (⌘C ⌘V ⌘W
⌘M ⌘Q work, a minimized window shows the app icon); with no window open it is menu-bar-only again. The Activity
window stops refreshing while it is minimized, covered or closed, and can be made small (about 600 x 440).

## Safety

- Software priority only. It cannot damage the hardware; heat and power stay under the chip's own control.
- Only your own user's processes. Root and other users' processes are unreadable and never touched.
- Never touched, no override: the frontmost app and everything inside it, Finder/Dock/WindowServer and
  other system parts, anything under /System or /usr (except Spotlight and Photos analysis workers),
  security tools, local AI hosts (Ollama, LM Studio, llama.cpp, ...), the app itself, and your own list.
- Reported in the log but not slowed: browsers, calls, music/video, audio apps (any name with "audio" or
  "sound"), code editors, terminals, Claude.
- Anything holding a "keep the Mac awake" assertion (playback, calls, downloads) is left alone.
- Before each change it re-checks that the process is still the same one (PID plus start time).
- Quitting, SIGTERM and turning the switch off all release everything first. If the app is killed hard,
  the next launch releases whatever it had slowed (`~/Library/Application Support/BGOptimizer/slowed.json`).
- Only one copy runs at a time.
- **When you change a job yourself**, the engine decides again, whatever the window showed: system, security,
  local AI, protected and in-front jobs are refused; browsers, calls, media, editors and anything keeping the
  Mac awake need your confirmation; the job must still be the same process (PID plus start time); it is
  refused while the app is switched off or in Observe only. Every action and every refusal is written to the
  log. Only your own user's processes are ever listed or changed.

## Automated checks

    ./BGOptimizer/tests/run.sh

Checks the translations, the log (private permissions, one line per entry, clear), the row menu, startup items
(parsing, the rules for changing, a real read), and the rules for changing jobs by hand (with harmless sleeper
processes; your real Finder is used only to confirm it is refused). About a minute. See also `SECURITY-REVIEW.md`.

## Test from Terminal

    "build/BG Optimizer.app/Contents/MacOS/BGOptimizer" --headless --dry-run --seconds 120

Options: `--threshold 50` `--sustain 12` `--interval 5` `--seconds N` `--dry-run` (report only).
Dev aids that draw windows to PNG files without starting an engine: `--snapshot-panel <prefix>`,
`--snapshot-windows <prefix>` (Activity, Settings, welcome); add `--lang en` or `--lang uk` to force a
language; `--snapshot out.png` draws the Settings window.

Translations: texts are in `BGOptimizer/Resources/en.lproj/App.strings` and `uk.lproj/App.strings`
(the key is the English text; Ukrainian plural forms are `.one`, `.few`, `.many`). To add a language, copy
`uk.lproj`, translate it, add it to `AppLanguage` and the Language picker, and list it in `Info.plist`.
`python3 tools/check_strings.py` checks that nothing is missing, placeholders match and nothing is stale;
`build.sh` runs it first and stops if it fails.

## What was tested (M1, macOS 27)

Tested with CPU-burner scripts: slowing (scheduler priority 31 to 4), release on calm-down, release on
quit and SIGTERM, recovery after `kill -9`, single instance, protection lists including user-added names,
DMG integrity and the signature of the app inside it, the Settings window (drawn to an image).

Also tested (panel build): per-job Restore sticks (priority 31 to 4 to 31, not slowed again over the next
15 s), Observe only leaves a busy job untouched, and the panel drawn to images in light and dark mode for
the on, nothing-slowed, paused and observing states.

Also tested (Activity and welcome build): the engine's activity rows against real processes (a busy job
went Watching, then Slowed; Edge showed Left alone; the editor in front showed "never touched"); the system
readings against `pmset`, `sysctl`, `vm_stat` and System Information (battery time remaining, health,
cycles, memory pressure and memory in use agree); both windows drawn to images in light and dark mode; a
throwaway copy of the app opened both windows for 8 seconds without crashing.

Also tested (Ukrainian build): the translation checker (168 keys and 6 plural phrases, all translated,
placeholders match); a test of the language code (Ukrainian plural forms for 1, 2, 4, 5, 11, 12, 14, 21, 22,
25 and 101; positional arguments; decimal comma; fallback to English for a missing key; switching between
languages); your real saved settings still load unchanged after the update; every screen drawn to images in
both languages, light and dark, and fixed where Ukrainian text was too long; a throwaway copy started in
Ukrainian opened the Activity, Settings and welcome windows for 8 seconds without crashing.

Also tested (changing jobs yourself), with harmless sleeper processes and your real Finder, each result read
back with `ps`: a normal job slowed (priority 31 to 4) and restored; Finder refused and unchanged; a wrong
identity refused; a browser-like job refused without confirmation and slowed with it; a manual slow-down not
released after the 3 s of quiet that would release an automatic one; protecting an app released it and blocked
further slow-downs; quitting restored everything. Clear log tested in a separate folder (your real log was
not touched). A throwaway copy in Ukrainian with the app on and the Activity window open collected real rows
for 14 seconds without crashing.

You tried the first version of the **…** menu in the real window: it worked, but the menu opened far from
the row you clicked (outside the window). It is now a native popup opened at the mouse. The contents of the
menu were tested for every kind of row (normal, browser-like, slowed, system, on your list) in both
languages. After you rebooted, the app log showed the login item starting the app (4:43:13 PM, 17 seconds
after login) and the app releasing everything on shutdown (4:41:38 PM).

Not tested by hand yet: where the new popup appears, the confirmation dialog and the banner in the real
window, column sorting, and Hide idle processes (the code paths and the engine rules behind them are tested).
Right-clicking a row does not open the menu yet; use the **…** button.

Ukrainian wording was written by an AI assistant and checked for grammar rules and layout, not reviewed by a
native speaker: please have one look it over.

The panel's accent-colored switch was confirmed from your own screenshot of the running app.

Not tested: the Language picker clicked in the real app (the code path that switches the language while the
app runs is in place and its parts were tested, but I could not click it), clicking inside the Activity window, the welcome window's Get started button, the Settings
controls, changing settings while jobs are running, turning "Launch at login" on, the panel's Restore
button in the real app (only the engine call behind it), and release when a slowed app is brought to the
foreground (written, not exercised). Not tested on any chip other than the M1, and not on a Mac without a
battery (the battery tile is hidden there, by design, untried).

During testing the login item turned out to be registered once without a known cause (not reproducible);
it was switched off. The app now logs every login-setting change as `LOGIN` in the activity log.

## About describe.md

describe.md documents a Windows tool (registry, services, scheduled tasks, firewall, WMI, working-set
trimming), so most of it cannot work on a Mac. What was carried over: the safety design (protected
lists, foreground and audio exemptions, identity checks, restore on exit, crash recovery, action log).
Not carried over: RAM trimming (macOS compresses memory itself; 16 GB is rarely the bottleneck), freezing
processes, startup/service/firewall/registry tweaks, disk cleanup, translations.

## Older prototype

`bgcalm.py` is the earlier Python command-line version (`python3 bgcalm.py --apply`). The app replaces it.
