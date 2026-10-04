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

## Performance pass, 4 October 2026 (local Mac)

Changes from `docs/PERFORMANCE_AUDIT_2026-10-03.md`; its implementation-status table lists what changed per finding. Checked on a Mac with **Xcode 27.0 (27A266a)** and an **iPhone 18 Pro simulator on iOS 27**, so unlike the CI runs above this is the checked-in iOS 27 deployment target.

- `swift test`: **90 core tests passed, 0 failures**, including 12 new `PerformanceTests`: indexed validation still rejects misfiled, misdated and orphaned records; the note limit counts characters, not bytes; the store file is compact and exports are formatted; a commit over the size limit leaves the store readable; an oversized import is rejected before reading; Insights without pairs match the full summary and the pairs-only path matches it; Statistics' kept days; and the one-pass history matches the previous algorithm (kept as a reference in the test) on 300 generated habits with goal changes, pauses, freezes and archives. Two XCTest `measure` baselines cover validating 100,000 records and reading ten 10-year histories.
- `python3 scripts/check-project.py` passed; the project was regenerated for the new `Shared/UI/HabitSummaries.swift`.
- Unsigned app and widget simulator build succeeded with no new compiler warnings.
- First full UI run: 13 of 15 passed, 1 skipped (the opt-in Home Screen gallery) and `testWidgetCustomization` failed. With dashboard rows in a lazy stack, touching and holding a widget's check logged it instead of opening the widget menu (seen in the run's screen recording). An eager stack passed the same steps, so dashboard rows stay eager; a probe found compact tiles and card checks still open their menus in lazy stacks. Touching and holding a compact row's name did not open its menu even on the code before this pass; that was not investigated further.
- Final full UI run on the finished code: **14 passed, 1 skipped (opt-in Home Screen gallery), 0 failures**, including relaunch persistence through the background save queue, timer logging from the app and from the Live Activity's Finish, the share sheet with the new PNG exporter, and every screen and widget capture.
- Screenshots from the run (cards, compact, detail, statistics) were inspected: card and detail histories open on the latest week with month labels intact across chunk boundaries, and compact tiles stay in their day columns.

Not measured: tap latency, frame rate, hitches, memory or launch time on an iPhone. The comparison below compiles the shared core with `-O` on this Mac (Apple silicon), before (`02808fa`) and after, on synthetic data; it is the best of five runs (three for the slower rows) and does not measure the app, SwiftUI rendering or a device.

| Workload | Before | After |
|---|---|---|
| Validate 500 habits / 100,000 records | 28.1 ms | 12.6 ms |
| Validate 50 habits / ~66,700 records | 7.7 ms | 7.8–8.5 ms (no change) |
| Stats for 30 ten-year daily habits | 40 ms | 17–21 ms |
| Milestones for 30 ten-year daily habits | 56–58 ms | 18–19 ms |
| Statistics summary, one year, 30 habits | 45–47 ms | 18–22 ms |
| Insights, all time, 30 ten-year habits | 148–150 ms | 150–152 ms (no change: all 30 habits are pair candidates here) |
| One check-in transaction on the 66,700-record store | 239–243 ms | 175 ms, now off the main thread |
| That store's file size | 17.6 MB | 13.3 MB |

Each change still validates the whole snapshot once on the main thread so editors can keep their drafts; that is the 8 ms row above for a 66,700-record store and well under a millisecond for typical data. Skipping it for check-ins, whose engine calls already enforce their rules, is a possible next step if device traces show it.

## Theme and accent color, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on an **iPhone 18 Pro simulator, iOS 27**. Another change was in progress in the same working tree, so the app and UI tests were built from a clean copy of the previous commit plus only this change, with their own derived data.

- `swift test`: **93 core tests passed, 0 failures**, including the new `testAccentDefaultsToVioletAndRoundTrips`: the default accent isn't written; palette and `#RRGGBB` accents round-trip; empty, capitalized, malformed and over-long values are rejected.
- `python3 scripts/check-project.py` passed. Unsigned app and widget simulator build succeeded with no compiler warnings from source files.
- Full UI run: **16 passed, 1 skipped (opt-in Home Screen gallery), 0 failures**. This includes the new `testThemeAccent`: choose teal and Light, relaunch, both are kept, then Default and System. Every existing screen and widget capture also passed, plus the new `theme` capture.
- Screenshots inspected: the Theme page with the default, amber, teal and a custom crimson accent; Compact List Settings with mint; New Habit with yellow. On amber, yellow, mint and teal, text on accent fills is dark and readable. A first run showed the open Settings sheet keeping its old appearance after Light or System was chosen. Settings now takes the overview's scheme, and the captures show it switch at once to Light, and to dark under System on a dark simulator.

Not checked: the custom color picker was not driven by a test, and home-screen widgets with a non-default accent were not placed.

## Per-habit redraws, lighter check-ins and touch feedback, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on **iPhone 18 Pro simulators, iOS 27**. Other sessions were using the same working tree and the default simulator, so the app and UI tests were built from copies of this change, each with its own derived data and simulator.

- `swift test`: **93 core tests passed, 0 failures**. `testHiddenHabitsLeaveScreensButKeepTheirData` now checks that the shown data keeps every record, since screens find records only through their habit. Under load from two simulator builds, the icon search timing test once took 3.66 s against its 3.0 s limit; it passed in the final run.
- `python3 scripts/check-project.py` passed. Unsigned app and widget simulator build succeeded with no compiler warnings from source files.
- Full UI run on the finished app code: **17 passed, 1 skipped (opt-in Home Screen gallery), 1 failed**: a first version of the new `testHoldingACardOpensItsMenu`, whose tap on the status bar didn't close the menu. The final version of that test and `testCompactRowNameOpensHabitMenu` then passed twice each in a separate run. The two timer tests log "Publishing changes from background threads"; earlier full runs on the code before this change log the same warning.
- Redraws, counted by a temporary counter in each view's body on a copy of the app (not committed), tapping one habit's check: cards view, 8–12 card bodies before and 2 after; compact view, 50 day tiles before and 5 after.
- Touching and holding, on the previous code: holding a card's check logged progress and holding a compact row's name opened the habit. With the name and the check carrying the habit's menu themselves, every card hold made on a fresh launch opened the menu without logging (13 holds), but 2 of 5 holds made a few seconds after another menu closed ran the button instead: the check logged progress once (while another test run was finishing on the same Mac) and the name opened the habit once. A version that made the name and check menus with a primary action (SwiftUI `Menu` with `primaryAction`) did no better: one of its 6 such check holds logged progress (also while another build was running), and a tap outside failed to close its menu 3 times in 8, against 6 of 6 for the context menu. It wasn't kept. With Drag to Reorder off, that version had no misfires and no failed closes in 3 rounds, so the cards' drag-to-reorder interaction may be involved; that wasn't followed up. The committed tests hold the card's name and check, each from a fresh launch, and the compact row's name; earlier versions of the card test closed the menu between holds, and failed once on the close and once when the check hold logged progress.

Shared core compiled with `-O` on this Mac (Apple silicon), one run before and one after on synthetic data, so the validation row shows run-to-run spread; not the app, SwiftUI or a device:

| Per check-in, 50 habits / 66,650 records | Before | After |
|---|---|---|
| `withoutHidden` with one habit hidden | 8.36 ms | 0.01 ms (records are kept, not copied) |
| Full validation on the main thread | 7.4–11.2 ms | not run for check-ins (the save still validates) |
| History refill for the summaries cache | every visible habit (1.6–2.0 ms for 6 cards) | the tapped habit only |

Not checked: the streak, list and month layouts' checks under touch and hold (they sit in lazy grids like the cards did); tap latency, frame rate, hitches, memory and launch time on an iPhone.

## Liquid Glass mode, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on a dedicated **iPhone 18 Pro simulator, iOS 27**. Another change was in progress in the shared working tree, so this change was built and tested in a clean clone, then rebased onto `3488649` and tested again.

- `swift test`: **94 core tests passed, 0 failures**, including the new `testLiquidGlassIsOffByDefaultAndRoundTrips`:
  - glass that was never set isn't written;
  - every field round-trips, and turning the mode off keeps the look;
  - out-of-range transparency or strength and malformed tints are rejected.
- `python3 scripts/check-project.py` passed. Unsigned app and widget simulator build succeeded with no compiler warnings from source files.
- Full UI run after the rebase: **19 passed, 1 skipped (opt-in Home Screen gallery), 0 failures**. This includes the new `testLiquidGlass`:
  - turn the mode on, then choose Clear and the teal tint;
  - relaunch, and all three are kept;
  - choose Frosted, then turn the mode off and its options disappear.
- **Glass off matches the previous commit pixel for pixel.** Screenshots of the overview, Compact List (and its settings sheet), Settings, Insights and habit detail compared with zero differing pixels. The Theme page differs only by the new section.
- Screenshots inspected:
  - **Overview:** System, Clear + teal and Frosted + teal in dark; Frosted in light.
  - **Other screens:** the Theme page with the live preview; New Habit (disabled Save on glass); habit detail in light.
  - **Glass sheets:** Compact List Settings, and the routine sheet in dark and in light with the accent tint.
  - **Fix found:** a first pass showed clear glass turning the violet plus a deep, saturated blue, so prominent actions now always use regular glass.
- Accessibility: with Reduce Transparency on (set through the simulator's accessibility defaults), the clear switcher turns solid and card text no longer shows through. With Increase Contrast on, the glass darkens and its edges sharpen.

Not checked: scrolling hitches with glass on were not measured with Instruments, and the custom tint picker was not driven by a test.

## Dragging cards by the history grid, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on dedicated **iPhone 18 Pro simulators, iOS 27**. Another change was in progress in the shared working tree, so this change was built and tested in a copy of `0d691c2` plus this change only. It reached `dev` inside `facc5f9`, with the bottom-switcher change, and its tests were run again there. Other simulator builds kept the Mac heavily loaded for most of the session (load average 10–112); the results say which runs had the Mac to themselves.

- `python3 scripts/check-project.py` passed. No core code changed, so `swift test` wasn't rerun.
- **Dragging works from the grid.** The new `testDraggingACardByItsGridReordersHabits` holds Gym Day's grid for a second, moves it slowly onto Push-Ups and holds there for a second. It then checks that Gym Day moved below Push-Ups and is still there after a relaunch. It passed running alone (22 s) and in the full run.
- **The same drag failed on three other layouts:**
  - the code before this change (`0d691c2`), where the whole card was draggable and carried the menu;
  - the grid draggable while the card around it still carried the menu;
  - the grid draggable and carrying its own menu.

  Each time, the menu opened and the card never moved. On the code before this change that happened with a quick drag and with the slow one, so dragging to reorder probably didn't work before. Those runs were all made under load; that code wasn't retried alone.
- **Repeated holds:** a probe holds the name, the check and the grid in turn, closing the menu between holds, for 3 rounds.
  - On the final layout, the name and the check opened the menu 3 of 3 times each, nothing logged or opened the habit, every close worked, and the grid opened no menu. The probe was clean both alone and in one run under load.
  - On the layout with the card still carrying the menu, the check logged progress once, in round 1, under load.
- **Misfires and load:**
  - Every hold that ran a button instead of opening the menu, here and in the previous section, happened while the Mac was heavily loaded. One was a fresh-launch name hold on an earlier version of this change, which opened the habit after 12 seconds.
  - With one simulator running, none happened, so the previous section's suspicion of drag to reorder is withdrawn. An app too busy to run the hold timer before the finger lifts is a likelier cause, but this isn't confirmed.
  - A guard that ignored presses held half a second or longer didn't stop that misfire: it times the press when the app handles it, so a stalled app sees a short press. It would also have ignored long taps, such as from people who set Haptic Touch to Slow, so it wasn't kept.
- Full UI run on `0d691c2` plus this change, under load: **20 passed, 1 skipped (opt-in Home Screen gallery), 0 failures**. The two timer tests still log "Publishing changes from background threads", as before.
- On `facc5f9`, the drag test, both hold tests and `testSwitcherOpensDashboardAndExploreInPlace` passed, under load.

Not checked:
- dragging and holding on an iPhone;
- the lifted card's look against HabitKit.
