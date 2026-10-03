# Validation record

Cloud checks, 3 October 2026 (Asia/Kolkata):

- Swift 6.2.3 on Linux, Swift 5 language mode: **41 XCTest cases passed, 0 failures**. Tests exercise the real shared engine, local-day/DST arithmetic, decimal precision, goal history, streaks, quit thresholds, notes, archive pauses, validation, concurrent increments, exports, failed transactions and corruption recovery.
- All native Swift source files passed the Swift compiler's syntax parser. This checks syntax, not SwiftUI/AppIntents type availability or an iOS binary.
- Deterministic Xcode project generation, source membership, Info.plist/entitlements/privacy manifest parsing, shared scheme XML, reference JSON, all collected research hashes and local gallery links passed.
- All four requested UI skill packages were validated and installed; their SKILL.md instructions were read. Versions are in `UI_SKILLS.json`.

The Linux Swift compiler's initial parallel debug run encountered a process-statistics crash in this hosted environment. The single-worker build with debug information disabled completed and executed the full tests. No platform-specific workaround changes were made to the app's source for this issue.

Mac CI, 3 October 2026 (Asia/Kolkata):

- [GitHub Actions run 37073838015](https://github.com/iyashwant/habbit-buddy/actions/runs/37073838015), source commit `be1f40c2aab6a2cef67773fc6f44103eb882f4df`, completed successfully.
- **41 XCTest cases passed, 0 failures** on macOS; deterministic project and research checks passed.
- **Unsigned simulator build succeeded** for the HabitBuddy app and HabitBuddyWidgets extension, including SwiftUI, Charts, WidgetKit and App Intents compilation for arm64 and x86_64. Both targets emitted App Intents metadata.
- The runner had **Xcode 26.6 (17F113), iOS Simulator SDK 26.5**. CI explicitly overrode deployment to 26.0 for source compilation; the checked-in project still targets **iOS 27.0**. This is not evidence of an iOS 27 runtime test.
- The widget's `appintentsnltrainingprocessor` logged `Could not archive SSU artifacts`; this did not fail the build. The app's training step and overall build completed. Siri/App Shortcuts discovery and extension metadata packaging still need native installation testing; no runtime success is inferred from the build.

iOS 27 simulator/device testing remains pending. Visual comparisons, signing, notification delivery, widgets, Siri, file pickers, PNG exports and accessibility require the checks in `MAC_TESTING.md`. The CI build does not establish a verified 1:1 match to HabitKit.

## Rebuilt visual pass after workspace reset

All 112 files from the last pushed commit were restored and matched their Git blob hashes before edits. Source and reference changes were pushed to dev as commit `e471ef8`, followed by native build and CI configuration fixes. The first native batch on `4c7a025` produced seven real iPhone 17 / iOS 26.5 screenshots and passed the completion/relaunch UI test. Its overall suite failed: a saved habit was below the lazy list viewport, the share panel did not open, and statistics rendering timed out. Those findings were used to revise the UI and tests; that batch is not claimed as a passing suite.

Commit `ac868e8` caches statistics, reuses the immutable civil-date formatter, keeps weekday labels fixed while contribution history scrolls, refines month indicators and sharing, and adds editable category icons. Its 44 core tests and screen-capture test passed, but the native share test still failed. The captured screen confirmed that the panel was not presented. Commit `e28db103` uses the exported image as the sheet's item source and a uniquely identified share button; the test waits for an actual system Copy or Save Image action before capturing and asserting.

## Latest complete Mac run

[GitHub Actions run 37114456851](https://github.com/iyashwant/habbit-buddy/actions/runs/37114456851), source `e28db103ec22d7082a2cb50abc835f8e48c9116e`, **completed successfully** on 3 October 2026 (UTC).

- **44 core XCTest cases passed, 0 failures.** Includes schema-one settings compatibility, card overrides, and the cached statistics summary regression in addition to the original domain/persistence coverage.
- **All 4 native UI tests passed, 0 failures.** Completion toggling survives relaunch; invalid editor input keeps the draft; searchable icon selection and a saved habit work; the exported PNG opens real native sharing actions; the main screen capture batch succeeds.
- **Unsigned app and widget simulator build passed** for arm64 and x86_64. The widget extension contains four widget definitions. This proves compilation, not successful physical-device placement or shared-container signing.
- **17 native screenshots** were recovered and visually inspected: 13 principal dark screens, icon selection, Cards/Welcome in light mode, and the system share panel. Original screenshots are 1206 × 2622 on iPhone 17 / iOS 26.5, using isolated synthetic data dated 2026-08-18. JPEG copies, a contact sheet, hashes and source/run metadata are in `research/habitkit/07_visual_audit/native_screens/`. The `.xcresult` CI artifact retains the original PNG attachments.
- The project/research checks passed on this source commit. The final documentation/screenshot-only commit is checked separately with `python3 scripts/check-project.py`; it does not change runtime code.

The runner used **Xcode 26.6 (17F113), iOS Simulator SDK/runtime 26.5**. CI regenerates its temporary project for deployment 26.0; the checked-in project remains **27.0**. No iOS 27 simulator/device success, exact pixel parity, native reminder delivery, widget installation, Siri execution, physical-device signing or full accessibility validation is inferred from this run.
