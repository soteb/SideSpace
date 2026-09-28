# Validation report — 2026-09-27

## Documentation follow-up (2026-09-28)

- Added the English `README.md` and rewrote `README_zh.md` against the current
  implementation and recorded validation status. Removed obsolete Linux-only
  build claims and clarified the UI-scoped timers.
- Checked both documents' local links, section anchors and code-fence balance.
  Checked Mermaid delimiter balance only; GitHub Mermaid rendering was not tested.
- Parsed all four standalone SVG mockups successfully and inspected native
  Quick Look renders. Quick Look cropped full-size thumbnails; proportional
  temporary preview copies were used to inspect the complete artwork.
- Illustrations are explicitly labeled simulated, with example monitor data;
  they are not application screenshots or evidence of native acceptance.
- No application code changed and no application tests were repeated for this
  documentation-only follow-up.

## Follow-up: selectable Dock display (2026-09-28)

- Added built-in-default / external-UUID Dock display selection, disconnected
  selection retention, and a single-display margin override. The cross-screen
  switching order is unchanged; the selection does not move or inspect the Dock.
- `bash scripts/test-core.sh`: PASS, 160057 checks. Added cases for selected vs
  unselected external displays, display reordering, negative coordinates, existing
  system reservations, disconnected selection, single-display fallback,
  external-only configurations, and insufficient remaining window width.
- The inherited `CC=/opt/homebrew/opt/llvm/bin/clang` Sanitizer run remained
  CPU-active without a result and was terminated. Apple Clang initially needed
  SDKROOT to find SDK headers. The final command
  `CC="$(xcrun --find clang)" SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" SANITIZE=1 bash scripts/test-core.sh`
  passed all 160057 checks without sanitizer diagnostics.
- `bash scripts/build.sh`: PASS with final sources; arm64 application generated,
  ad-hoc signed, strict signature verification and Info.plist lint passed.
- Initial Xcode build inherited Homebrew LLVM and failed with SDK module errors.
  `env -u CC -u CXX bash scripts/build-xcode.sh`: BUILD SUCCEEDED with Apple tools.
- `plutil -lint Resources/*.lproj/Localizable.strings`: all 11 languages passed.
- The native checklist was updated, but no real Chrome movement, display
  unplug/replug, application preference persistence across restart, menu visual
  acceptance, macOS 27 runtime test, or memory test was performed for this change.
  No installed application or running instance was replaced.

## Follow-up: blue application icon (macOS, 2026-09-27)

- Replaced `Resources/AppIcon.png` with the blue design from
  `design/icons-v2/SideSpace-AppIcon.png`, resized to 1024 × 1024.
- Generated all ten standard iconset entries (16–512 pt at 1x and 2x) and
  replaced `Resources/AppIcon.icns`. Initial sandboxed iconutil conversion
  reported Invalid Iconset; conversion outside the sandbox succeeded.
- Extracted the resulting ICNS and verified its 1024-pixel PNG matches
  `Resources/AppIcon.png` byte-for-byte.
- `bash scripts/build.sh`: PASS, including strict ad-hoc signature verification
  and Info.plist lint. Verified the bundled ICNS matches the source resource.
- No installed copy was updated, no application was restarted, and Finder icon
  cache behavior was not tested. Core tests were not repeated for this asset-only
  change; the previous test results and limitations below remain applicable.

## Follow-up: margin-window menu icon (macOS, 2026-09-27)

This follow-up supersedes the original Linux-only compilation status below for
this local build, but does not establish full native acceptance.

- Host: macOS 26.6.2; selected macOS SDK: 27.0.
- Replaced `Resources/MenuBarIcon.pdf` with an 18 × 16 point vector margin-window
  symbol. The existing template-image loader continues to supply system tinting.
- Compiled the build-time artwork generator with `-Wall -Wextra -Werror` and
  generated the resource successfully.
- `bash scripts/build.sh`: PASS; arm64 application compiled, linked, ad-hoc
  signed, and passed strict codesign verification and Info.plist lint.
- `cmp Resources/MenuBarIcon.pdf build/SideSpace.app/Contents/Resources/MenuBarIcon.pdf`:
  PASS; the application bundle contains the replacement artwork.
- `bash scripts/test-core.sh`: PASS, 160041 checks.
- `SANITIZE=1 bash scripts/test-core.sh`: started, but produced no result after
  several minutes; its test process was still CPU-active and was terminated.
  Sanitizer validation is incomplete, not a pass.
- No installed application was replaced or restarted. Actual menu-bar appearance,
  the native checklist, macOS 27 runtime compatibility and memory tests were not
  verified in this follow-up.

## Environment

- Linux x86_64, not macOS.
- Clang 17.0.0 (Swift toolchain LLVM build).
- No Xcode, macOS SDK, AppKit runtime or WindowServer available.
- No `.app` executable was built in this environment. The ZIP contains source only.

## Executed successfully

1. `bash scripts/test-core.sh`
   - Compiled the portable C layout core and tests with `-std=c11 -Wall -Wextra -Werror`.
   - Result: `PASS: 160041 checks (deterministic + 20,000 randomized layout cases)`.
   - This comprises 41 deterministic assertions and 160,000 assertions across randomized cases.
2. `SANITIZE=1 bash scripts/test-core.sh`
   - Repeated the same tests with AddressSanitizer and UndefinedBehaviorSanitizer.
   - Same PASS result; no sanitizer diagnostics were emitted.
3. `plutil -lint Config/Info.plist SideSpace.xcodeproj/project.pbxproj`
   - Both property lists passed.
4. Shared Xcode Scheme XML parsed successfully.
5. PBX build graph/source references inspected programmatically.
   - All 9 native compile units appear exactly once in the application target.
   - Source files, SDK framework references, configuration files and product references resolve structurally.
6. `bash -n` on every delivered `.sh` and `.command` file.
   - All passed syntax checks.
7. `scripts/build.sh` tested on Linux.
   - Exited with status 1 and an explicit requirement for macOS/macOS SDK 26+.
   - This is an environment guard check, not a macOS build result.
8. Release package integrity checked with ZIP CRC verification after packaging.

## Not executed / not verified

- Objective-C and macOS-only C source compilation against an Apple SDK.
- Xcode target builds, local code signing, codesign validation or notarization.
- Runtime compatibility on macOS 26 or 27.
- Chrome activation, Carbon hotkeys, shortcut-recorder interaction, TCC permissions,
  login-item registration or actual multi-display AX move/resize.
- Real memory footprint, wakeups, CPU usage or latency measurements.
- Intel builds, virtual displays, Sidecar or mirrored display configurations.

The native source has been written and reviewed against the intended APIs, but
structural checks and portable tests do not substitute for macOS compilation or
end-to-end tests. Follow `MAC_TEST_CHECKLIST.md` before treating the app as a
verified release. Do not report this artifact as a precompiled or notarized app.
