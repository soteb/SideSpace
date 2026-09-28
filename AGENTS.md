# SideSpace development rules

The user-facing app name is SideSpace. The Chinese name is 有间. The installed app, executable, and bundle identifier are SideSpace (`com.jimmyliang.SideSpace`). Saved settings use the preferences domain `com.jimmyliang.SideSpace`.

This is a narrowly scoped native macOS menu-bar utility. Preserve the user contract.

- C geometry/state machine, Accessibility, hotkey and preferences core; Objective-C for AppKit/NSWorkspace/ServiceManagement and orchestration. No Swift, Electron, WebView, Rust, packages, subprocesses or script runtime in the app.
- macOS deployment target is 26.0. The intent is runtime compatibility with 26 and 27; verify both on hardware. Do not claim unperformed platform or memory tests.
- Default margin is 50 logical points. Default hotkey is Option+Command+A. The second preset is Option+A, and the third is Control+Option+Command+Right. All three stay selectable, and a custom shortcut remains available.
- If Chrome is not frontmost, the first press only reveals it. Never continue into layout in the same invocation.
- On the built-in display, first normalize the full frame; only a subsequent press on an already-normalized frame moves to an external display. Dock margin applies only to the user-selected display (built-in by default, external selection persisted by UUID); other displays use visibleFrame. A single connected display always uses the margin. External → internal preserves the existing switching order. Disconnected selections remain saved.
- Compare full frame with 3 pt tolerance. Frame coordinates in the C core are global top-left AX coordinates. Never use NSScreen.mainScreen as the global coordinate origin.
- Respect system visibleFrame. Recognize built-in displays using CGDisplayIsBuiltin; persist UUIDs rather than temporary display IDs.
- AppKit and settings UI on the main thread. AX IPC on the serial work queue, bounded retries, no permanent polling. Cancel stale operations on screen/sleep changes. Keep permission errors and actual resize failures visible.
- Balance every Create/Copy CF reference. Use ARC for Objective-C, and small autorelease pools around AX queue jobs. Do not cache window lists indefinitely.
- No public/private web-content reads, no tracking, no telemetry, no screenshot or input-monitoring requirement. System Accessibility permission is broader than this program's intended scope.
- Read `docs/VALIDATION_REPORT.md` and update it only with tests actually run. Run `bash scripts/test-core.sh`, `SANITIZE=1 bash scripts/test-core.sh`, macOS compile and the native checklist before release.
- Keep the native hotkey adapter replaceable. Do not use private CGS APIs to bypass OS activation or permission policy.
