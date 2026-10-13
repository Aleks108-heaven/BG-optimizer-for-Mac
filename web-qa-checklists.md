# Web UI QA Checklists

## Functional
- Forms: required/optional, max length, trim whitespace, paste, autofill, double submit, server-side vs client-side validation messages
- Navigation: deep links, back/forward, refresh mid-flow, multiple tabs, 404/500 pages
- State: session expiry, logout in another tab, cookies disabled, offline/slow network
- Errors: 4xx/5xx shown in plain language with a way to retry, rate-limit messages, no raw error text or stack traces
- Content: long text, Unicode/emoji, RTL, empty states, large datasets, time zones

## Accessibility (WCAG 2.2 AA)
- Keyboard: every control reachable, logical tab order, visible focus that is not hidden behind sticky bars (2.4.11), no keyboard trap, Esc closes dialogs
- Semantics: one h1, landmarks, labels tied to inputs, button vs link, table headers and captions
- Visual: contrast 4.5:1 for text (3:1 for large text, and for UI components and graphics); text resizes to 200% (1.4.4); content reflows at 320 CSS px wide, which is 400% zoom (1.4.10); no meaning by color alone
- ARIA: only when native HTML is insufficient; status messages announced without moving focus (4.1.3, live regions)
- Pointer: target size at least 24x24 CSS px (2.5.8); every drag has a non-drag alternative (2.5.7)
- Forms and help: do not ask users to re-enter information already given (3.3.7); login does not depend on solving a puzzle or remembering by memory alone (3.3.8); help is in the same place on every page (3.2.6)
- Motion: respect `prefers-reduced-motion`; nothing flashes more than 3 times a second
- Tools: axe-core, Lighthouse, WAVE catch only part of the issues, so also do a manual keyboard pass and a screen-reader pass (NVDA, VoiceOver)

## Performance budgets (typical targets, measured at the 75th percentile of real-user data; use lab runs to catch regressions)
LCP <= 2.5 s | INP <= 200 ms | CLS <= 0.1 | TTFB <= 800 ms | JS bundle: investigate above ~170 KB gzipped on mobile (a rule of thumb, not a standard)

## Compatibility matrix (pairwise)
Browsers: Chromium, Firefox, WebKit | Viewports: 360, 768, 1280, 1920 | OS: Windows, macOS, Android, iOS | Locales: en, de, ar (RTL), ja | Display: light and dark, `prefers-contrast`, forced colors

## Client-side security
CSP present, no secrets in bundle/source maps, cookies HttpOnly/Secure/SameSite, no open redirects, sanitized innerHTML, SRI on third-party scripts, mixed content blocked, framing blocked (`frame-ancestors`), `postMessage` checks the sender's origin, no tokens in `localStorage` unless the risk is accepted.

## Native desktop app UI (use when the target is a macOS app, not a page)
- Keyboard: Tab reaches every control with Full Keyboard Access on; `⌘,` opens Settings; `⌘W` closes a window; Esc dismisses a popover; every menu item has a visible shortcut where one exists
- VoiceOver: every control has a name; tabs and switches announce their selected/on state; the menu-bar item has a label and value (for example "BG Optimizer, on, 2 jobs slowed"); table rows read as a whole
- Appearance: light and dark; Increase Contrast; Reduce Transparency; Reduce Motion; the user's accent color if the app follows it
- Windows: resizable where it makes sense, remembers size and position, works on a second display and in full screen
- Menu-bar apps: the item can be hidden when the menu bar is crowded (notched MacBooks), so every action must also be reachable another way (Settings window, relaunching the app)
- Lifecycle: first launch, launch at login (including the System Settings approval step), quit restores everything the app changed, one copy only, sleep/wake, crash then relaunch
- Text: strings 30% longer than English (German) and right-to-left still fit; no text is truncated without a tooltip or full view
