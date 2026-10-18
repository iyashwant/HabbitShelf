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

## Dragging dashboard widgets, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on a dedicated **iPhone 18 Pro simulator, iOS 27**. The first simulator made for this was deleted partway through by work outside this change, so the later runs used a second one. Other work loaded the Mac early in the session (load average up to about 90); the final runs had it at 6–30.

- `python3 scripts/check-project.py` passed. No core code changed, so `swift test` wasn't rerun.
- **iOS 27's `reorderable()` and `reorderContainer` were tried first and dropped.** Inside the custom layout, every widget was laid out small: the modifier dropped each widget's size, set as a layout value and then as a container value. A press-and-drag didn't reorder either. They also need iOS 27, and the app supports iOS 26.
- **Menu, then drag:** the order of the modifiers decides it. With `.contextMenu` before `.onDrag`, a hold opened the menu and moving on lifted the widget. With `.onDrag` first, the menu opened and the widget never lifted.
- **Synthesized holds hand over unreliably.** Over six drags with holds of 0.7, 1.0 and 1.5 s, five reordered; the miss (1.5 s) left the menu open. An earlier version of the test passed 1 of 3. The test now gets three tries, each from a fresh launch, and says when a try misses. The final test passed 3 of 3 on its own and once in the full run, each time on the first try.
- **Live captures during a drag** (`simctl io screenshot` while the test held the widget) showed:
  - the native menu with the lifted widget;
  - the menu closing as the finger moved;
  - a dashed outline moving to the place under the finger while the other widgets slid aside;
  - the switcher fading, and the drop landing.
- **Fixes found this way:**
  - the drop handler checked a value captured before the drag began, so no drop was taken;
  - the switcher took drags near the bottom, so widgets beneath it couldn't be reached;
  - fading the switcher made iOS report the drag leaving and re-entering the page, which put the order back in a loop;
  - a drag held at the bottom scrolled until the finger was below the last widget, which also counted as leaving.
- **`testDraggingADashboardWidgetReordersIt`** drags the Today ring onto Deep Work and checks it moved and that the menu closed. After a relaunch it checks the order was saved and that holding without moving still opens the menu.
- Full UI run: **22 passed, 1 skipped (opt-in Home Screen gallery), 0 failures**, including the existing dashboard check, add, customize and duplicate tests and the habit-card hold and drag tests. The two timer tests still log "Publishing changes from background threads", as before.

Not checked:
- dragging on an iPhone;
- iOS 26, since no iOS 26 simulator runtime is installed;
- text dragged in from another app being refused.

## Hold-then-drag for habit cards, 4 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on a dedicated **iPhone 18 Pro simulator, iOS 27**, with the Mac otherwise quiet (load average 6–8).

- **The menus stay on the card's parts; the drag goes around the whole card.** With the menu inside and the drag outside, a hold that opened a part's menu handed over to the drag, as on the dashboard, and the whole card was the lifted preview. Earlier layouts in the previous section put the drag on the grid or inside the menu, and the card never moved.
- **The direction matters, as elsewhere in iOS.** Holding Gym Day's name opened the menu below the row, over Push-Ups. Dragging down onto Push-Ups moved into the menu and highlighted its items (Edit Today), three tries out of three, and the card didn't lift. Dragging Push-Ups up onto Gym Day lifted it on the first try.
- **Live captures during that drag** showed:
  - the menu with the whole card lifted;
  - the menu closing and the switcher fading as the finger moved;
  - the dashed outline taking the top place while Gym Day slid down;
  - the drop leaving Push-Ups first.
- **`testHoldingACardOpensItsMenu`** now also holds the grid. With Drag to Reorder on, the grid opens the menu, without logging or opening the habit.
- **`testDraggingACardReordersHabits`** replaces the grid-drag test. It holds Push-Ups' name, drags up onto Gym Day's grid, checks the card moved and the menu closed, and that the order survives a relaunch. Like the dashboard test, it gets three tries from a fresh launch. It passed 3 of 3, each on the first try.
- **XCUITest waits 60 s after a hold on anything that can be dragged.** This also applies to the dashboard change above, where it went unnoticed.
  - On the dashboard, a hold that opened the menu took 61 s with a drag attached (`onDrag` or `draggable`) and 2–3 s without. Tapping a menu item took 64 s against 1 s. A tap 3 s later went through at once.
  - XCUITest logs "App animations complete notification not received" and carries on. Nothing moves on screen, and writing state when the drag is prepared isn't the cause; the drag lift iOS prepares while the menu is open is the likely one, but that isn't confirmed.
  - So `testHoldingACardOpensItsMenu` takes about 227 s instead of 20 s, and `testWidgetCustomization` about 155 s instead of 26 s (measured on `ab5fbb6`, where it passed 4 of 4).
- **`testWidgetCustomization` with the drag passed 5 of 7, then 2 of 2 after the change below.**
  - One failure: the menu wasn't there after the hold.
  - The other: a quick check icon was missing just after a fresh build. Three later rounds that listed the Gym Day buttons around the same tap always found all four.
  - Its hold now gets a second try.
- Full UI run before that retry: **21 passed, 1 skipped (opt-in Home Screen gallery), 1 failure** (`testWidgetCustomization`, the missing menu). Afterwards, `testWidgetCustomization`, `testDraggingACardReordersHabits` and `testHoldingACardOpensItsMenu` each passed twice.

Not checked:
- dragging on an iPhone, including how a finger moving down past the menu behaves;
- whether the slow holds affect anything outside XCUITest;
- iOS 26.

## Performance follow-ups and iPhone measurements, 4 October 2026 (local Mac and iPhone)

Checked with **Xcode 27.0 (27A266a)** on dedicated **iPhone 18 Pro simulators, iOS 27**, and on an **iPhone 15 Pro running iOS 27.0.1**. Another session was working in the shared folder, so this change was built and tested from its own worktree on top of `f21536d`. Other simulator builds, a virtual machine and Docker kept the Mac loaded (load average 7–112).

- `swift test`: **95 core tests passed, 0 failures**, including the new `testWidgetKindsReloadOnlyForTheHabitsTheyShow`. `python3 scripts/check-project.py` passed. App, widget and test builds produced no compiler warnings from source files.
- **Timer warning gone.** Both timer tests logged "Publishing changes from background threads" in every earlier full run. With `TimerSessions.stop` posting on the main thread, they logged it 0 times, in two runs.
- **Holding a check in the other layouts.** The new `testHoldingAChecksOpensTheMenuInEveryLayout` holds Gym Day's check in the streak, list and month layouts, each from a fresh launch, and a compact day tile. Every hold opened the menu without logging or opening the habit, on the code before and after this change. Those layouts have no drag, which the cards' misfires involved, so their menus were left as they were.
- Full UI run on this change before the last two edits: **21 passed, 5 skipped (the opt-in Home Screen gallery and the four performance tests, opt-in), 1 failed**: `testWidgetCustomization`, whose added widget was the ninth and so wasn't drawn until it scrolled into view. Deferred drawing was then removed; the dashboard tile is as on `dev` again apart from reading the store through Observation. The runner restarted once under memory pressure during `testBackfillDaysBeforeHabitStart`. On the code before the dashboard edit, `testBackfillDaysBeforeHabitStart`, `testCompactListSettings`, `testCompletionPersistsAfterRelaunch`, `testDraggingACardReordersHabits` and `testDraggingADashboardWidgetReordersIt` then passed; the other reruns were stopped and the full suite wasn't run again on the final code, at the owner's request (to be run later). The final code builds without warnings.
- **iPhone 15 Pro**, `PerformanceUITests` (Debug build with `-O`, since the fixtures exist only in Debug builds; 5 runs, 9–10 taps for check-ins). The large fixture is thirty habits over five years, about 40,000 logged days.

| | Sample fixture | Large fixture |
|---|---|---|
| Launch until the habits show ("First load") | 153 ms | 304 ms (cards), 325 ms (streak layout) |
| Launch until the first frame responds | 0.53 s | 0.47 s |
| Check-in, tap until its screen update has run | 25 ms (22–27) | 116 ms (112–120) |
| Flinging the cards | 0 hitches, 85 fps, 107 MB peak | 0 hitches, 85 fps, 145 MB peak |
| Flinging the dashboard (14 widgets)¹ | 0 hitches, 84 fps, 45 MB peak | |

¹ Measured with widgets after the first eight drawn only once they scrolled into view. That wasn't kept, so the dashboard as committed draws all of them at once; that wasn't measured again with this fixture.

- Before this change, on the same phone and the sample fixture, with an earlier version of the tests: launch to the first responsive frame 0.540 s (0.541 s after); flinging the cards hitched in 1 of 5 runs (4 hitches, 108 ms) and in none after. Flinging the default dashboard (12 widgets, all drawn at once, as committed) showed no hitches at 84 fps, peaking at 50.9 MB; the lower 44.8 MB and CPU time measured after came with the deferred drawing that wasn't kept. The large fixture and the check-in and first-load signposts were added afterwards, so they have no before figures.
- **Check-ins with long histories are slow.** 116 ms is over the audit's 50 ms target. Timing each step in a scratch build on the simulator put the store's own work (copying the snapshot, the change, publishing) at 4–10 ms; the rest, 40–75 ms there, came after it, in SwiftUI's update of the tapped card. Not fixed in this change.

Not checked:
- the zoom transition frame by frame, with Reduce Motion, or opened from the dashboard;
- widget reloads on a real Home Screen (the UI tests skip widget reloads), and Instruments traces of launch, check-ins or the GPU;
- Release builds, other iPhones and iOS 26.

## Check-ins with long histories, 5 October 2026 (local Mac)

Checked with **Xcode 27.0 (27A266a)** on a dedicated **iPhone 18 Pro simulator, iOS 27**, from a separate worktree on top of `83d71d1` (another session was working in the shared folder). Other work kept the Mac loaded (load average 5–20). Not measured on an iPhone: the owner asked not to test on their phone.

- `swift test`: **96 core tests passed, 0 failures**, including the new `testSameSnapshotMeansACopyNotEqualRecords`. `python3 scripts/check-project.py` passed. The optimized app, widget and UI test build produced no compiler warnings from source files.
- **Cause.** Time Profiler attached to the app during `testCheckInLarge` (Debug build with `-O`): of 466 main-thread samples inside the 11 "Check-in" intervals, 361 (77%) were `BuddyData`'s `==`, mostly the records dictionary's. SwiftUI's AttributeGraph called it while comparing view values: the cards the overview's `ForEach` rebuilt (183), the views whose bodies ran (97) and the drag-to-reorder branch around each card (46); Observation's setter for `AppStore.data` added 35. With `ViewData` and the hand-observed `data`, a trace of the same test had no samples in `BuddyData`'s `==`; the largest piece of the store's own work left was copying the records for the change (about 2.5 ms per tap).
- **Check-in, tap until its screen update has run** (`PerformanceUITests`, Debug build with `-O`, 10 taps per run, two runs of each build alternating):

| | Before (`83d71d1`) | After |
|---|---|---|
| Sample fixture | 24 ms and 10 ms (8–45) | 11 ms and 9 ms (7–20) |
| Large fixture (thirty five-year habits) | 29 ms and 32 ms (25–39) | 12 ms and 12 ms (9–19) |

- A first tap after launch, which XCTest leaves out of its average, took 0.1–0.5 s in the traces before and after; most of it was the main thread waiting rather than working, and its work was one-time type setup.
- Profiling note: Time Profiler symbolicates the app only when attached to it (`xctrace record --attach <pid>`); a recording of all processes on the simulator left the app's frames as addresses.

Not checked:
- the iPhone figures (116 ms before), other devices, iOS 26 and Release builds;
- the full UI test suite on this change; only `PerformanceUITests`' check-in tests ran against it.

## Dashboard Today List density, 18 October 2026 (local Mac)

- Xcode **27.1 (27A9275)**, simulator SDK **27.1**, deployment target **26.0**: unsigned app and widget builds passed for arm64 and x86_64. Existing HomePager actor-isolation and OverviewView `UIScreen.main` warnings remain.
- `python3 scripts/check-project.py` and `git diff --check` passed.
- `bash scripts/check-ios.sh` stopped at the existing `IconSuggesterTests.testSuggestingIsFast` benchmark: 95 of 96 core tests passed; 3,000 suggestions took 6.00 seconds against its 3-second limit. Isolated retries also exceeded that limit (3.57 and 14.64 seconds) on this loaded Mac. No icon-suggestion or core behavior was changed.
- The UI test target compiled, including `testDashboardListFitsItsHabits`, which checks one-, three- and six-habit lists, check-button size, row spacing, the following widget's placement, and dark/light captures. `BUDDY_VISUAL_LIST_COUNT` selects those synthetic lists only within the existing debug audit store.
- Native visual and interaction verification is pending: the iPhone 18 Pro simulator booted but app installation and diagnostic process spawning stalled, including after restarting it. The existing Switcher SE3 simulator installed the app but stalled on launch. The selected dashboard UI run was interrupted before any test case executed. A simulator Home Screen screenshot is not app UI evidence; no screenshot parity is claimed.
