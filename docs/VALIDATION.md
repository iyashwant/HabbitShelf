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
