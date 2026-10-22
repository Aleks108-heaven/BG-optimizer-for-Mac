# BG Optimizer for Mac

A menu-bar app for Apple Silicon Macs. When a background job keeps one of your own processes busy (by default over
50% of a core for one minute), it puts that process in macOS background mode, so it runs at low priority on the
efficiency cores and your foreground work stays smooth. **It never kills anything, and every change is reversible.**

A slowed process goes back to normal when it comes to the foreground, when it calms down (under a quarter of the
threshold for a minute), when you pick "Give everything back now", when you switch the app off, or when you quit.

Written in Swift (SwiftUI and AppKit) with no third-party code. English and Ukrainian interface.

## Quick start

1. Open the [latest release](https://github.com/Aleks108-heaven/BG-optimizer-for-Mac/releases/latest) and download
   `BG-Optimizer-<version>-arm64.dmg` (Apple Silicon Mac, macOS 13 or newer).
2. Open the `.dmg` and drag *BG Optimizer* onto *Applications*.
3. macOS will refuse the first launch, because the app is not notarized by Apple. Run this once in Terminal, then open
   the app:

       xattr -dr com.apple.quarantine "/Applications/BG Optimizer.app"
       open "/Applications/BG Optimizer.app"

   Or try to open it, then use System Settings > Privacy & Security > **Open Anyway**.
4. Follow the welcome screen. The app starts switched off; *Observe only* is the safe way to begin.

Details, the checksum check and building it yourself are under [Install](#install).

## Install

**Requirements:** an Apple Silicon Mac (M1 or newer; the app is arm64 only, there is no Intel build) and macOS 13 or
newer. It is built for macOS 13+, but it has been run only on macOS 27 on an M1 MacBook. The GitHub workflow also builds it and
runs the automated tests on a macOS 14 runner.

### Option 1: download the installer (built by GitHub)

The workflow in `.github/workflows/build-macos.yml` builds the app on a GitHub-hosted Apple Silicon Mac, runs the
whole automated test suite and a start-up test of the finished app, and keeps the installer. In the repository on
GitHub, either open **Releases** and take the latest `BG-Optimizer-<version>-arm64.dmg` plus `SHA256SUMS.txt`
(a release is created when a tag such as `v1.0.0` is pushed), or open the **Actions** tab, pick the latest successful
run and download the `bg-optimizer-macos-arm64` artifact (it holds the same two files). Check the download against the
checksum file, from the folder that holds both:

    shasum -a 256 -c SHA256SUMS.txt

The checksum only shows that the download is not corrupted, because it comes from the same place as the installer. For
releases built after v1.0.0, GitHub also signs a build record that proves the `.dmg` was built from this repository
by this workflow. Check it before you remove the quarantine flag below (needs the GitHub CLI, `brew install gh`):

    gh attestation verify BG-Optimizer-<version>-arm64.dmg --repo Aleks108-heaven/BG-optimizer-for-Mac

Open the `.dmg` and drag *BG Optimizer* onto *Applications*.

**Opening it the first time.** The app is signed ad hoc (the minimum Apple Silicon needs to run it) but it is not
notarized by Apple, which needs a paid developer account. So macOS says it "could not verify BG Optimizer is free of
malware" and will not open it. That is Gatekeeper reacting to the download flag. Remove the flag once, in Terminal,
then open the app as usual:

    xattr -dr com.apple.quarantine "/Applications/BG Optimizer.app"
    open "/Applications/BG Optimizer.app"

Or, without Terminal: try to open it, then go to System Settings > Privacy & Security, scroll down and press
**Open Anyway** (it asks for your password). On recent macOS versions Control-click > Open no longer gets past this.
Do the same again after installing a newer version. macOS's policy check (`spctl`) rejects this build, as expected for
an app that is not notarized; the first launch on a second Mac has not been tested.

### Option 2: build it yourself (no warning)

An app you build yourself is not quarantined, so macOS does not warn. You need only the Xcode command-line tools, not
full Xcode:

    xcode-select --install                      # once
    git clone https://github.com/Aleks108-heaven/BG-optimizer-for-Mac.git
    cd BG-optimizer-for-Mac/BGOptimizer
    ./build.sh --install                        # builds and copies the app to ~/Applications/BG Optimizer.app
    ./build.sh --dmg                            # also builds dist/BG-Optimizer-<version>-arm64.dmg

Without any warning for other people the app must be signed with an Apple *Developer ID* and notarized by Apple. That
needs a paid Apple Developer Program account; the build script does not do it yet.

### Settings and removal

Settings, the protected list and the Launch at login choice are stored per Mac and are not copied; a new Mac starts
with the welcome screen. To remove the app completely: switch off Launch at login, quit it, delete
`~/Applications/BG Optimizer.app`, and delete `~/Library/Application Support/BGOptimizer`,
`~/Library/Logs/BGOptimizer` and the settings (`defaults delete com.alexxxela.bgoptimizer`).

## Use

A speedometer icon appears in the menu bar. The number next to it is how many processes are slowed.

**Click the icon** to open the panel: the on/off switch, a status line, and each slowed job with its CPU use, how long
ago it was slowed, and a **Restore** button (a job you restore is not slowed again until it calms down or exits).
Below are **Give everything back now**, Settings…, Activity… (⌘Y) and Quit. **Right-click (or control-click)** the
icon for the plain text menu, which also has Launch at login; it is the way in if macOS hides the icon on a crowded
menu bar.

The app starts switched OFF; choices are remembered. Launch at login may need approval in System Settings > Login
Items; keep the app in `~/Applications`, because login items remember the location. Every change to the login setting
is written to the log as `LOGIN`. Command line: `BGOptimizer --login on|off|status`.

**Settings window**

- *General*: on/off switch, launch at login, **Observe only** (the log shows what would be slowed; nothing is
  changed, and anything already slowed is given back), how busy (20-95% of one core) and for how long (30 s to 5 min)
  before a job is slowed, and what is slowed right now. Changes apply immediately.
- *Protected apps*: apps you never want slowed (type a name or choose an app), on top of the built-ins.
- *Language*: **System default, English or Українська** (Ukrainian). It switches at once, with no restart, and is
  remembered. The welcome screen has the same picker. "System default" follows the Mac's language list (the first of
  English or Ukrainian found). The log file and the Log tab stay in English on purpose; dialogs drawn by macOS itself
  (for example the Choose app panel) follow the system language.

**Activity window** (panel > Activity…)

- *Status tiles* about the Mac, refreshed every 5 seconds while the window is open: CPU load, memory (pressure level
  and GB in use), thermal state (whether macOS is throttling the chip), battery (charge, time left or to full, Low
  Power Mode, and health: condition, maximum capacity, cycle count) and free storage. A tile shows a warning symbol and
  wording, not just a color, when something needs attention. Battery health is read from the same source as System
  Information. Free storage counts space macOS can reclaim, like Finder does, so it is a little higher than `df`. In a tall window on the Processes tab the tiles are shown in full; in a small window and on the other tabs they become a one-line strip with the same readings and warning symbols (details in the tooltip), so the table keeps its room. Each tab's explanation is one line; **More** opens the full text.
- *Processes*: all of the user's own processes (not system or other users'), busiest first, with CPU use, **Memory** (the
  figure Activity Monitor shows, read only; click the header to see which use the most) and a status
  chip: Slowed, Watching, Would slow (observe only), Skipped (browsers, calls, media, editors, the app in front: never
  slowed automatically), Protected (system, security, local AI, the protected list: never slowed, even by you) or
  Normal, plus the reason in plain words. Click a column header to sort, filter by name, or hide idle processes. The
  engine builds these rows only while this window is visible.
- *Change a job* (the **…** button at the end of a row opens a native menu at the mouse). Only these reversible
  actions exist:
  - **Slow down now**: puts it in macOS background mode. For browsers, calls, media apps, editors and anything
    keeping the Mac awake there is a warning first (the default button is Cancel).
  - **Restore normal priority** for a job that is slowed.
  - **Never slow “app”**: adds the app (all of its processes) to the protected list. **Remove from the protected
    list** undoes it. If the job was slowed, it goes back to normal at once.
  - A job that cannot be changed shows why in the menu (for example "System process", "You are using it").

  A job slowed by hand stays slowed until you restore it, bring its app to the front, or it exits (it is not released
  just for being quiet). A banner above the table confirms or explains each action. There is no kill and no way to
  raise priority. Right-clicking a row does not open the menu yet; use the **…** button.
- *Startup*: everything that starts by itself at login or boot, apart from macOS's own items: agents and daemons from
  the user's and the system Library, and apps registered as login items. Each row shows what it is, when it starts
  (at login, kept running, on a schedule, on demand), whether it is running now, and whether it is on. **Only the
  user's own agents (in `~/Library/LaunchAgents`) have a switch**, because macOS lets an ordinary app change only those,
  with no password: switching one off tells launchd not to start it at the next login (`launchctl disable`), and it can
  be switched back on. It never stops what is running and never deletes anything. System-wide items and login-item
  apps show their state and a **Settings…** button that opens System Settings, because changing them needs an
  administrator. Security tools, macOS items and this app are locked. The list takes a few seconds to read and is read
  only when the tab is opened or Refresh is pressed.
- *Drivers*: what macOS keeps for third-party hardware and security software: system extensions (`systemextensionsctl
  list`), old kernel extensions in `/Library/Extensions`, and the root helper tools in `/Library/PrivilegedHelperTools`.
  Each row has a status: **Probably not in use** (switched off, and no app from the same maker is installed), **Maker's
  app not found**, Switched off, Waiting (for your approval, or to be removed at the next restart), Old type (a kernel
  extension), Enabled or Installed. **It only reads.** Removing a driver needs an administrator (and
  `systemextensionsctl uninstall` needs SIP switched off), so the app shows what it found and leaves the removal to the
  maker's uninstaller. It does not decide that a driver is *out of date*: that needs the maker's list of versions, and
  this app never uses the network, so it shows the version or the date for you to compare. Apple's own items are never
  listed. "Maker's app not found" can be wrong for an app kept in an unusual place; "Enabled" is only a guess about
  *use* for a helper tool, because macOS does not say whether one is used.
- *Storage*: what is taking space in **your own Library**: app caches, app logs, Xcode build files, and **possible
  leftovers** of apps you removed (settings, containers and caches whose maker has no app installed or running; for
  example what ESET or Malwarebytes leave behind). It is read only until you act: each row has **Reveal in Finder** and
  **Move to Trash…** (a confirmation first, Cancel is the default). Nothing is deleted and nothing is cleaned
  automatically; the Trash keeps the item until you empty it, so it can be put back. It is refused while Observe only is
  on, for an item used by a running app, for macOS's own items (`com.apple.`), this app's own files, an installed
  security tool's caches and logs, symbolic links, and anything outside the listed folders. Only direct children of
  `~/Library/Caches`, `Logs`, `Developer/Xcode/DerivedData`, `Application Support`, `Preferences`, `Saved Application State`,
  `HTTPStorages`, `Application Scripts`, `Containers` and `Group Containers` are ever looked at; `/Library` and system
  extensions are never touched (to remove those, use the vendor's uninstaller). "Possible leftover" is a guess from
  the name (a `com.`/`org.`/`net.` identifier whose maker has no installed app), so read the row before you move it. The
  size of another app's container is not read (macOS keeps it closed), and macOS may refuse to move one; do that in Finder.
- *Log*: the recent activity log, with **Clear log…** (asks first). The full log is
  `~/Library/Logs/BGOptimizer/actions.log` (rolls over at 1 MB).

**First launch.** On the very first start (no saved choice yet) a welcome window explains the safety rules and asks how
to start: *Observe only* (recommended) or *Start optimizing now*, plus Open at login, which is off unless ticked.
Nothing is applied until Get started is pressed; closing the window leaves everything off. `--first-run` shows it again.

**Dock and menus.** While an Activity, Settings or welcome window is open the app has a Dock icon and a normal menu
bar (⌘C ⌘V ⌘W ⌘M ⌘Q work, a minimized window shows the app icon); with no window open it is menu-bar-only again. The
Activity window stops refreshing while it is minimized, covered or closed, and can be made small (about 600 x 440).

## Safety

- Software priority only. It cannot damage the hardware; heat and power stay under the chip's own control.
- Only the user's own processes. Root and other users' processes are unreadable and never touched.
- Never touched, no override: the frontmost app and everything inside it, Finder/Dock/WindowServer and other system
  parts, anything under /System or /usr (except Spotlight and Photos analysis workers), security tools, local AI hosts
  (Ollama, LM Studio, llama.cpp, ...), the app itself, and the protected list.
- Reported in the log but not slowed automatically: browsers, calls, music/video, audio apps (any name with "audio" or
  "sound"), code editors, terminals.
- Anything holding a "keep the Mac awake" assertion (playback, calls, downloads) is left alone.
- Before each change it re-checks that the process is still the same one (PID plus start time).
- Quitting, SIGTERM and turning the switch off all release everything first. If the app is killed hard, the next
  launch releases whatever it had slowed (`~/Library/Application Support/BGOptimizer/slowed.json`).
- Only one copy runs at a time. The log and state files are private to the user (700/600).
- **When a job is changed by hand**, the engine decides again, whatever the window showed: system, security, local AI,
  protected and in-front jobs are refused; browsers, calls, media, editors and anything keeping the Mac awake need
  confirmation; the job must still be the same process; it is refused while the app is switched off or in Observe only.
  Every action and every refusal is written to the log.

- **Storage is the one place that removes files from where they were**, and only into the Trash, one item at a time, after
  you confirm. See the *Storage* bullet above for what is refused; the rules are checked again at the moment you press
  the button, not only when the list was drawn.

See `SECURITY-REVIEW.md` for the attack surface, findings and performance measurements.

## Automated checks

    ./BGOptimizer/tests/run.sh

Checks the translations, the log (private permissions, one line per entry, clear), the row menu, the Storage rules (what is
offered, what is never offered, every refusal for Move to Trash, in a stand-in home folder), startup items
(parsing, the rules for changing, a real read), the security-tool name rule (a name must start a word), the Drivers tab
(reading `systemextensionsctl list`, the decision for every kind of row, stand-in folders, a real read), the rules for changing jobs by hand (with harmless sleeper processes;
a system process of the current user is used only to confirm it is refused), and a start-up test of the finished app
(windows, Dock icon, minimize and restore). About a minute. On a machine without a Finder, a per-user launchd domain or
a window server, the parts that need them are skipped with a message. Every section has a time limit, and on GitHub
Actions each section's result is also copied into an annotation on the run page. Outside programs the app runs
(`launchctl`, `sfltool`, `system_profiler`, `systemextensionsctl`) are stopped after a time limit instead of being waited for forever.

## Development

Dev aids: `BGOptimizer --headless [--dry-run] [--threshold N] [--sustain N] [--interval S] [--seconds N]` runs the
engine without the UI. `--snapshot-panel <prefix>` and `--snapshot-windows <prefix>` draw the windows to PNG files
without starting an engine (add `--lang en` or `--lang uk`). `--selftest-window` opens the Activity window, minimizes,
restores and closes it, and logs what the app did. The environment variable `BGOPT_LOG_DIR` moves the log folder
(used by the tests).

**Translations** are in `BGOptimizer/Resources/en.lproj/App.strings` and `uk.lproj/App.strings` (the key is the English
text; Ukrainian plural forms are `.one`, `.few`, `.many`). To add a language, copy `uk.lproj`, translate it, add it to
`AppLanguage` and the Language picker, and list it in `Info.plist`. `python3 BGOptimizer/tools/check_strings.py` checks
that nothing is missing, placeholders match and nothing is stale; `build.sh` runs it first and stops if it fails.

Design notes and the reasoning behind decisions are in `DESIGN.md`. The QA notes at the top level (`macos.md`,
`security-checklist.md`, `web-qa-checklists.md`, `qa-reviewer.md` and others) are the checklists used for the review.
`bgcalm.py` is the earlier Python command-line prototype (`python3 bgcalm.py --apply`); the app replaces it.

## Status and limits

Tested on an M1 MacBook (16 GB) running macOS 27 with CPU-burner scripts, harmless sleeper processes and the real
system. Verified there (the 247 automated checks plus manual checks):

- slowing (scheduler priority 31 to 4), release on calm-down, on quit and on SIGTERM, recovery after `kill -9`,
  single instance, protection lists including user-added names;
- per-job Restore sticks (not slowed again over the next 15 s); Observe only leaves a busy job untouched;
- the Activity rows against real processes (Watching, then Slowed; a browser shows Skipped; the app in front is never
  touched) and the system readings against `pmset`, `sysctl`, `vm_stat` and System Information;
- changing jobs by hand: slowed and restored with the priority read back with `ps`; a system process refused and
  unchanged; a wrong identity refused; a browser-like job refused without confirmation and slowed with it; a manual
  slow-down not released for being quiet; protecting an app released it and blocked further slow-downs;
- startup items: a real switch off and on with the result read back from launchd; macOS items, security tools, this
  app, mismatched or out-of-folder files, path tricks, odd labels and symbolic-link escapes are refused;
- Ukrainian plural forms (1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101), positional arguments, decimal comma and the
  fallback to English; settings saved by an older version still load; every screen drawn to images in both languages
  and both appearances;
- the finished app opened its windows, minimized, restored and closed them without crashing, with the Dock icon and
  background work behaving as described above;
- the menu-bar panel's accent-colored switch and a popup menu opening at the mouse were confirmed in the running app
  by a user.

Not tested by hand: the Drivers tab clicked in the real app (sorting, the filter, Open Login Items settings), reading kernel
extensions from a real `/Library/Extensions` (the development Mac has none; the logic is tested on stand-in folders), the Storage tab clicked in the real app (Reveal in Finder, the confirmation, Move to Trash; the rules behind
them are tested), moving another app's container to the Trash (macOS may ask or refuse), the final right-aligned placement of the row menu (an earlier placement was confirmed), the confirmation dialog and the banner in the real window, column sorting, Hide idle processes,
the Language picker clicked in the real app, the welcome window's Get started button, the panel's Restore button in
the real app (only the engine call behind it), turning Launch at login on from this version, release when a slowed
app is brought to the foreground, a Mac without a battery (the battery tile is hidden there), any chip other than the
M1, any macOS other than 27, and a second Mac (the GitHub workflow builds and tests the app on macOS 14, but nobody has yet opened the
downloaded installer by hand on another Mac).

The Ukrainian text was written with AI assistance and has had only partial review by a native speaker; corrections are
welcome (edit `uk.lproj/App.strings` and run the translation checker).

## License

MIT. See `LICENSE`.
