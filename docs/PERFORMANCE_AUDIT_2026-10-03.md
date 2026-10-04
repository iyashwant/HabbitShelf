# Habit Buddy: speed and smoothness audit

Audited 2026-10-03 against `dev` source commit [`6112bb5371aa5a9ed82933c0b824e24bda1effb8`](https://github.com/iyashwant/habbit-buddy/commit/6112bb5371aa5a9ed82933c0b824e24bda1effb8). The local checkout was synchronized to the exact remote commit and tree before review. This report changes documentation only.

The largest opportunities are removing synchronous database work from the main actor, avoiding repeated history calculations during view updates, and bounding rendering work to the content currently visible. Those changes should improve check-ins, navigation, search and scrolling while retaining the reference appearance. Their actual latency and frame-rate gains require measurements on an iPhone.

## Scope and evidence

Reviewed all 24 app Swift files, all 14 shared Swift files, both widget source files, the core and UI tests, project generation/build configurations, and architecture/design/parity documentation. The review covers launch, foreground reloads, logging, every overview layout, detail/month/year history, Dashboard, Explore, Insights, calendar, notes, milestones, routines, timer/Live Activity, settings, imports, exports, reminders, widgets, controls and Shortcuts.

Validation evidence:

- `python3 scripts/check-project.py` passed after synchronization: 186 project objects, project/plist/scheme checks, research checksums, JSON and gallery links.
- [GitHub Actions run 37139832981](https://github.com/iyashwant/habbit-buddy/actions/runs/37139832981) passed for the audited source: 66 core tests and 9 UI tests, zero failures; the simulator app/widget build also succeeded.
- That run used Xcode 26.6 and an iOS 26.5 simulator with an explicit CI deployment-target fallback. The checked-in app targets iOS 27. A successful fallback build is useful validation, but does not establish iOS 27 performance or compatibility on a device.
- Release configurations already use `-O`, and the Profile scheme selects Release. There is no evidence that a missing Release optimization flag is the problem.
- This Linux workspace cannot run Xcode, iPhone Instruments or native scrolling benchmarks. No launch-time, tap-latency, FPS, hitch-rate, memory-peak or energy measurements are claimed here. Existing test durations are suite durations, not performance benchmarks.

“Confirmed” below means a path or algorithm is present in source. It does not mean a visible hitch has been reproduced. “Profile” identifies work whose actual cost needs a trace. P0/P1/P2 are implementation priorities for this performance effort, not production incident classifications.

## Implementation status (4 October 2026)

The fixes below landed on `dev` after this audit. The findings table that follows is kept as audited. "Done" means the source change is in place and covered by the tests in `docs/VALIDATION.md`; none of these changes has been profiled on an iPhone yet, so the device plan at the end still applies before claiming latency or frame-rate gains.

| Finding | Status | What changed |
|---|---|---|
| Check-ins block the UI | Done | `AppStore.change` applies a change to the snapshot on screen, then a serial persistence queue runs it again in a locked transaction on the latest file. Queued changes are reapplied over each saved snapshot; a failed save is dropped and reported. Toggles decide from the saved amount. The haptic no longer waits for the disk. Reminder title and message save when editing ends, not per keystroke. |
| Linear record-to-habit validation | Done | ID index; key and note-length checks without per-record strings. Check-ins (`AppStore.log`) skip the full check on the main thread, because the engine checks each value it writes; the save still validates everything. The store and daily backups are compact JSON; exports stay formatted. |
| Whole-database publishing | Mostly | Screens key background work on `AppStore.revision`, and widget/reminder refreshes are skipped for app-only settings. Each change names the habits it touched, and `AppStore.version(_:)` counts changes per habit; cards, compact rows, streak rows, month cards and dashboard designs skip redrawing unless their habit, its options or the date changed (simulator: 2 card bodies per tap instead of 8–12, 5 compact tiles instead of 50). The store still publishes one snapshot, so parent views re-evaluate their lists; Observation is not adopted. |
| Lifetime stats and streaks in view bodies | Done (on the main thread) | `Engine.history` reads each habit once for stats, streaks and milestones (three passes become two). The store's `HabitSummaries` cache keeps each habit's result until that habit or its days change, so a check-in recomputes one habit. It is computed lazily on the main thread, not precomputed off-main. |
| Explore badges | Done | Captions are computed off the main thread per snapshot. |
| Eager long lists | Mostly | Compact rows, per-habit notes, milestones, routines and the day/routine sheets are lazy. Dashboard rows stay eager: in a lazy stack, touching and holding a widget's check logged it instead of opening the widget menu (simulator UI test). Each dashboard design now redraws only when one of its habits changes. |
| Full-history heatmaps | Done | 16-week chunks in a lazy stack; the oldest chunk may start up to 15 weeks early in the pre-start shade so all chunks share one width. |
| Statistics | Done | Summary computed off-main per habit/year/snapshot; the all-habits grid reads kept days from the summary instead of building a temporary database. |
| Insights stale results | Done | One cancellable request per range, habit, snapshot and day; stale results are dropped; a refreshing indicator shows. Pairs use only the 30 candidates, are cached per range and snapshot, and have unique IDs; months are indexed directly. |
| Notes search | Done | Index built off-main per snapshot; filtering runs off-main 120 ms after typing pauses. Icon search strings are built once. |
| Unbounded PNG exports | Done | Layout is measured before allocation and scaled to at most 24 million pixels; Year Review shares 12 habits (24 in Grid) per image; encoding and writing run in the background; progress and a double-tap guard. |
| Saved file larger than the decoder accepts | Done | Commits over 64 MiB are refused before touching the file; imports and backups are size-checked before reading. |
| Competing reminder reconciliation | Done in-process | `ReminderCoordinator` runs one reconciliation at a time with latest-data semantics and changes only requests whose content or time differ. Separate processes (intents) still reconcile independently. |
| Widget store reads and reloads | Partly | One repository per process, entries sort active habits once, app-only settings skip reloads, and the midnight refresh uses calendar day addition. Data changes still reload every widget kind. |
| Timer finish race | Done | The session is claimed inside the store's locked transaction, so app and Live Activity can't both log it. A shared coordinator for start-during-finish is not added. |
| Synchronous launch, reload, import and export | Done | All run on the persistence queue; launch shows the empty canvas until loaded; imports read and decode off-main; the Lucide and Font Awesome catalogs load separately. Font registration still runs at launch. |
| Repeated sorting and lookups | Done | `activeHabit(_:)`, per-habit key prefixes, an ordered goal cursor in the history pass, set membership for chosen habits, one calendar month model. |
| Feedback and touch | Done | Haptics fire immediately, the check-in animation respects Reduce Motion, and compact day tiles take the whole 38-point pitch. Flat-style buttons, now including checks and compact day tiles, dim and press in to 97% over 0.16 s (Reduce Motion keeps only the dimming); streak counts roll to new values. Holding a card's name, check or grid, or a compact row's name, now opens the habit menu; in the lazy lists it used to open the habit or log the check. In the simulator, a hold just after another menu closed still ran the button in 2 of 5 tries; see `docs/VALIDATION.md`. |
| Render and layout polish (P3) | Not changed | Still needs a GPU/layout trace. Month and year grids now reuse their day marks for the VoiceOver label. |

Persistence jobs emit a "Persistence job" signpost interval for Instruments, and `PerformanceTests` adds XCTest baselines for validating 100,000 records and reading ten-year histories.

## Optimizations already present

Preserve these improvements rather than rebuilding them:

- Modern civil-day arithmetic uses integer calculations. Display date formatters are shared. The old advice to allocate fewer date formatters per grid cell is already addressed.
- `BuddyRepository` caches a decoded snapshot by exact file bytes and validation day. This avoids repeated decoding for unchanged files and retains detection of external writes.
- `AppStore` coalesces widget/reminder work after a 350 ms tap burst and has a background-transition flush path. Daily backup pruning runs only when a new snapshot is created.
- Cards, month overview, streak overview, detail month history, year history and the global notes timeline already use lazy containers in their principal lists.
- Dense summary grids use `Canvas`. Charts read cached monthly/hourly summary values instead of recalculating each chart mark.
- Insights calculations already run in a detached task. Its remaining problems are cancellation, result ordering and unnecessary work.
- The app timer updates a localized one-second `TimelineView`; it does not publish the whole database every second. Live Activity clocks use system timer text driven by dates.
- The app works locally, with no network request needed for a check-in. Bundled fonts/icons support the reference design without runtime downloads.

## Prioritized findings

Locations refer to the audited commit. Shared causes are grouped so that one fix is not counted repeatedly across screens.

| Priority | Finding and evidence | Improvement | Confidence |
|---|---|---|---|
| P0 | **Check-ins block the UI while saving the entire store.** [AppStore.swift:25](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Services/AppStore.swift#L25), [Repository.swift:94](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Repository.swift#L94), [Repository.swift:117](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Repository.swift#L117) | Execute ordered persistence commands on a dedicated worker; publish UI state on MainActor. Give immediate local feedback with explicit pending/failure handling. | Confirmed synchronous path; magnitude needs profiling |
| P0 | **Every transaction validates every record using a linear habit lookup.** [Repository.swift:54](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Repository.swift#L54) | Build a habit-ID dictionary once; retain full validation initially. Separate compact internal encoding from formatted exports. | Confirmed O(records × habits) lookup |
| P1 | **One change publishes the whole database to many screen dependencies.** [AppStore.swift:5](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Services/AppStore.swift#L5), view `@EnvironmentObject` subscriptions and whole-data `onChange` handlers | Supply small per-habit/per-screen inputs and revisions; avoid publishing unchanged reloads. Adopt Observation with deliberately scoped properties. | Confirmed broad dependency; trace actual update fan-out |
| P1 | **Lifetime stats/streaks run in view bodies.** [Engine.swift:44](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Engine.swift#L44), [Engine.swift:93](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Engine.swift#L93), [HabitWidgets.swift:183](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/HabitWidgets.swift#L183), [HabitDetailView.swift:36](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/HabitDetailView.swift#L36) | Cache per-habit derived summaries off-main; reuse across cards, Dashboard, detail and widgets. | Confirmed repeated history traversal |
| P1 | **Explore computes badges for all active histories before opening a feature.** [ExploreView.swift:12](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/ExploreView.swift#L12), [ExploreView.swift:14](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/ExploreView.swift#L14), [Insights.swift:131](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Insights.swift#L131) | Provide a cached Explore summary; calculate milestone detail when needed and reuse the result. | Confirmed three-pass daily milestone path |
| P1 | **Some long lists eagerly build every row.** [DashboardView.swift:19](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/DashboardView.swift#L19), [OverviewView.swift:174](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/OverviewView.swift#L174), [NotesView.swift:15](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/NotesView.swift#L15), [MilestonesView.swift:12](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/MilestonesView.swift#L12), [RoutinesView.swift:12](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/RoutinesView.swift#L12), [HabitsCalendarView.swift:113](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/HabitsCalendarView.swift#L113) | Use lazy rows/List where content can grow; preserve stable identity, sizing, gestures and reference styling. | Confirmed eager containers |
| P1 | **Full-history heatmaps draw every week, including offscreen weeks.** [Heatmap.swift:45](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/Heatmap.swift#L45), [Heatmap.swift:118](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/Heatmap.swift#L118) | Divide history into stable week/month chunks and render visible chunks plus a small prefetch region. Cache cell state before drawing. | Confirmed full-loop draw; raster cost needs profiling |
| P1 | **Statistics still does expensive synchronous work and constructs a temporary database to draw a grid.** [StatisticsView.swift:71](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/StatisticsView.swift#L71), [StatisticsView.swift:76](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/StatisticsView.swift#L76), [Statistics.swift:17](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Statistics.swift#L17) | Build summary and aggregate grid cells off-main; pass a small render model directly to the grid. | Confirmed allocation/traversal path |
| P1 | **Insights can publish stale results after selection/range changes.** [InsightsView.swift:31](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/InsightsView.swift#L31), [InsightsView.swift:36](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/InsightsView.swift#L36), [InsightsView.swift:43](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/InsightsView.swift#L43) | Use one cancellable request keyed by range, selection, revision and day; reject obsolete completions. | Confirmed missing cancellation/result guard; race not reproduced |
| P1 | **Notes search rescans, sorts and groups the database per keystroke.** [NotesTimelineView.swift:13](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/NotesTimelineView.swift#L13), [NotesView.swift:9](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/NotesView.swift#L9) | Maintain an indexed notes snapshot; search off-main with a short debounce and latest-result protection. | Confirmed synchronous work |
| P1 | **Large PNG exports have unbounded height and synchronous rendering/encoding.** [YearReviewView.swift:30](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/YearReviewView.swift#L30), [YearReviewView.swift:50](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/YearReviewView.swift#L50), [WeeklyRecapView.swift:47](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/WeeklyRecapView.swift#L47) | Enforce a pixel/memory budget; paginate large exports, cache inputs, show progress and prevent duplicate renders. | Confirmed unbounded export; peak memory not measured |
| P1 | **A saved file can exceed the size the decoder accepts.** [Repository.swift:75](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Repository.swift#L75), [Repository.swift:111](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Repository.swift#L111) | Check encoded size before atomic replacement, preserving the old store on failure; preflight imported file sizes. | Confirmed missing write-size guard |
| P2 | **Reminder reconciliation is only serialized inside one AppStore path.** [AppEnvironment.swift:37](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Apple/AppEnvironment.swift#L37), [OverviewView.swift:97](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/OverviewView.swift#L97), [SettingsView.swift:204](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/SettingsView.swift#L204) | Route all reconciliation through one coordinator, discard older revisions and apply a notification diff. | Confirmed competing entry points; overlap not reproduced |
| P2 | **Widget/intent requests repeatedly open and decode the full store, and all kinds reload after every write.** [AppEnvironment.swift:6](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Apple/AppEnvironment.swift#L6), [AppEnvironment.swift:27](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Apple/AppEnvironment.swift#L27), [HabitBuddyWidgets.swift:12](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Widgets/HabitBuddyWidgets.swift#L12), [HabitIntents.swift:35](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Apple/HabitIntents.swift#L35) | Reuse a process-local repository safely, resolve habits once, prepare compact entries and reload only affected kinds/controls. | Confirmed work; system scheduling needs device testing |
| P2 | **Timer finish has no idempotent claim shared by app and Live Activity actions.** [HabitTimer.swift:60](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Apple/HabitTimer.swift#L60), [TimerController.swift:41](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Services/TimerController.swift#L41) | Serialize timer commands and record a unique session completion token atomically with the log. | Potential duplicate-log race; not reproduced |
| P2 | **Launch/reload/import/export perform synchronous file work; first icon access loads both catalogs.** [AppStore.swift:19](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Services/AppStore.swift#L19), [Design.swift:111](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/Design.swift#L111), [SettingsView.swift:76](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/SettingsView.swift#L76), [SettingsView.swift:191](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/SettingsView.swift#L191) | Stage data work on the persistence worker; keep usable/loading/error states explicit; separate small chrome icon data from editor search data. | Confirmed paths; launch contribution needs profiling |
| P2 | **Repeated active-habit sorting, ID lookup, goal lookup and record-key construction add overhead.** [Models.swift:78](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Models.swift#L78), [Models.swift:124](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Models.swift#L124), [Models.swift:218](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Models.swift#L218), [Engine.swift:231](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/Core/Engine.swift#L231) | Reuse active/by-ID snapshots; traverse ordered goal intervals efficiently; optimize hot key/default lookup paths after sampling. | Confirmed repetition; relative cost needs profiling |
| P2 | **Feedback and touch handling can feel inconsistent.** [Design.swift:203](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/Design.swift#L203), [Design.swift:238](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/Shared/UI/Design.swift#L238), [AppStore.swift:62](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Services/AppStore.swift#L62), compact day buttons | Add consistent pressed states, prepare haptics before interaction, isolate animations and enlarge invisible hit regions where spacing permits. Respect Reduce Motion. | Confirmed control styles; touch accuracy needs device testing |
| P3 | **Some render/layout polish may contribute GPU or allocation cost.** heatmap mask, surface overlays, `FlowLayout`, accessibility summaries | Profile first; cache measured layout/cell summaries or simplify equivalent compositing only where traces show a cost. | Profile only; no GPU bottleneck established |

## Storage and the critical tap path

The current check-in sequence is:

1. A SwiftUI button calls `quickLog` on MainActor.
2. `change` synchronously enters `repository.transaction`.
3. The repository acquires both an in-process lock and an exclusive file lock, reads the entire file, compares cached bytes, and potentially decodes/validates it.
4. The first write of the day also creates a full daily backup.
5. The mutation runs, all data is validated, all data is encoded with pretty printing and sorted keys, and the file is atomically replaced.
6. The complete database is published, an animation transaction is returned, and only then is the haptic delivered.

The decode cache improves step 3 but does not remove the read, comparison, validation, serialization, atomic write or possible lock wait. A widget/Shortcut holding the file lock can therefore delay the app's UI. Changing a layout or theme uses this same path. Reminder title/body text fields bind directly to persisted settings ([SettingsView.swift:139](https://github.com/iyashwant/habbit-buddy/blob/6112bb5371aa5a9ed82933c0b824e24bda1effb8/HabitBuddy/Views/SettingsView.swift#L139)), so a single typed character also takes this path.

Recommended first implementation: a dedicated serial persistence worker with explicit commands such as toggle, increment, save-day and update-settings. Each command reads and resolves the latest authoritative state inside the transaction. Simply putting synchronous work in `Task {}` on MainActor, or adding `async` to the existing method, does not establish off-main execution.

For fast feedback, maintain an ordered pending-command overlay over the latest committed snapshot, or disable the relevant action briefly while showing a pending state. If using optimistic updates, rebase remaining commands after each committed response, roll back/report failures, and test rapid counted taps. Do not publish an old completed snapshot over a newer pending change. Existing yes/no `quickLog` reads `old` before the fresh locked transaction; resolve toggle semantics inside that transaction when refactoring to avoid stale decisions after external writes.

Keep cross-process locking, atomic replacement, backup recovery and transactional import. Do not debounce away progress taps. Draft cosmetic/settings text locally and commit a validated value on editing completion or via an ordered coalescing command; flush pending commits within the supported background execution lifecycle.

Replace per-record `habits.first(where:)` validation with a dictionary lookup. This removes the record-to-habit O(R × H) component without weakening validation. Compact internal JSON can remove formatting overhead and excess bytes while formatted portable JSON exports remain available. Incremental validation is a later step requiring explicit dependency rules: goal/start/archive changes can affect many historical records. A SQLite/WAL store with record-level writes is a possible later architecture if device profiles show that whole-file persistence still dominates; it should not precede the smaller fixes and a migration/recovery design.

The decoder rejects files above 64 MiB, while `commitUnlocked` does not enforce that limit. Count and per-note limits alone do not bound the aggregate file size. The app can therefore save a file that a fresh repository instance or later launch rejects. Check encoded bytes before touching the original file. For imports, inspect file metadata before reading it all, then perform bounded decoding/validation on the worker while preserving security-scoped access for the necessary read.

## Derived data and view dependencies

`Engine.stats` traverses lifetime days for totals and again for streak segments. For daily habits, `Engine.streak` calls that same lifetime stats method. `Milestones` calls stats and adds another traversal for completion milestones. Computing these in a body makes their cost recur when selection, presentation state, settings or the shared store changes.

Specific improvements:

- Build a shared per-habit summary cache for stats, cadence streaks, milestones and year grids. Compute it from an immutable snapshot off-main and publish only the appropriate current result.
- `HabitWidgetContent` computes a streak before its `kind` switch, including kinds which do not use that streak. Move calculations into only the relevant branches as well as caching them.
- Explore needs only a badge count and small recap/note summaries. Its navigation hub should consume cached summaries rather than computing detailed histories synchronously.
- Statistics already caches chart bins, but `refreshSummary` is synchronous. Its aggregate heatmap additionally copies a database value, filters its entire record dictionary and creates synthetic `Record` values inside body evaluation. A dedicated array of grid cells avoids those persistence-shaped allocations.
- The all-habits calendar calculates daily progress for cells and recalculates the month in its summary. Reuse one computed month model for both. Year grids likewise can reuse cell state for drawing, stats and accessibility counts.
- Routine cards/buttons/strips repeatedly calculate progress and reconstruct `data.active` while resolving each member. Build an active/by-ID snapshot once and reuse one routine summary.

Use explicit revisions and bounded caches. Include the relevant habit/record revision, date range/year, civil today, week start, and any rule-dependent settings in a cache key. Recompute for backfill, historical goal edits, pauses, archive/restore, freezes, imports, deletion, midnight and relevant timezone/locale changes. Preserve the existing difference between successful-day stats and weekly/monthly period streaks. Quit clean days are derived even without stored records; a cache based only on record counts would be incorrect.

`@Observable` can help with finer property tracking, but changing the annotation while every view still reads one large `data` property does not solve the core dependency. Expose per-habit display models, screen summary models and small settings properties. Whole-data `onChange` also involves synthesized equality over the stored collections; use a meaningful revision/request key instead. Verify the actual dependency reduction in the SwiftUI instrument.

## Scrolling and rendering

Convert the eager Dashboard outer rows, Compact overview rows, per-habit notes, milestone overview, routines, day-habit sheet and routine-member sheet into lazy lists with stable IDs. Long horizontal filters/routine strips can use lazy horizontal stacks when necessary. Do not change fixed, small settings groups or the eight-row onboarding page just to make everything lazy.

Cards and detail already have lazy outer containers, but a lazy card can still contain one enormous full-history Canvas. `ContributionHistory` creates a Canvas as wide as the complete history, and its draw closure explicitly visits every week. Viewport clipping does not eliminate that application loop. A tiled/windowed history can retain access to every earlier date, fixed weekday labels, month labels, latest-week anchoring and the same tile pitch. Keep a few neighboring chunks prefetched so scrolling does not replace one hitch with another. Avoid creating a large raster texture for the entire history through blanket `drawingGroup()`.

Month dots and other noninteractive tiny summaries are suitable for compact precomputed Canvas data. Keep the accessible buttons and editable day labels in interactive calendars. Retain scroll position across a check-in or settings update; avoid changing scroll/container identity as a shortcut to refresh content.

Gradients, masks, rings and rounded shapes need GPU profiling before any appearance change. `FlowLayout` currently measures children during both sizing and placement with an empty cache; a proposal-sensitive measurement cache is a targeted improvement if a large calendar habit legend shows significant layout cost. Accessibility summaries that rescan the same cells can consume cached counts.

## Insights, search and asynchronous correctness

Insights already offloads its CPU calculation. However, cancelling `.task(id:)` does not cancel the separately detached work, and there is no generation check before assigning the result. The additional `onChange` creates untracked refresh tasks. Rapidly selecting All/Year/30 Days, or receiving a record update during calculation, can let an older computation finish last and replace newer content.

Use one managed computation request including revision, selection, range and civil day. Propagate cancellation into long loops and verify the request is still current before publishing. Show a small refreshing state instead of silently presenting old values under a new range. Keep the previously valid content if appropriate while updating, but label its state accurately.

Split selected-habit metrics from global pair analysis: the selected path currently builds a second full `InsightsSummary` merely to obtain pairs. The core also allocates tracked/lapse sets for every habit, although only the first 30 participate in pair comparisons. Build those sets only for candidates; reuse a cached pair analysis for selections. Month indexing can be calculated directly instead of repeated twelve-element string searches. Bitsets or ordered day indices are optional later optimizations if allocations dominate.

`ForEach(pairs, id: \.first)` is not a unique identity: `(A,B)` and `(A,C)` share it. Use a stable composite pair ID. This is a correctness improvement for seamless list updates, independently of performance.

Notes timeline filtering, sorting, grouping and the habit-with-notes list currently happen in body computation per search change. Build an index when notes/habit metadata change, with a habit-ID set and searchable normalized fields. A roughly 100–150 ms debounce is a proposed starting point for result filtering, not for text input itself. Cancel obsolete searches and preserve row/section identity. Icon search similarly reconstructs concatenated keyword strings for all 3,273 icons on every query; precompute the search strings once, retain lazy results, and profile whether background filtering is warranted.

## Widgets, notifications and timer coordination

The existing AppStore coalescer is useful, but does not globally serialize `NotificationService.reconcile`. Foreground activation, permission settings, the recap toggle and intents also invoke reconciliation. Each reconciliation removes all `buddy.*` requests and sequentially adds up to 60 replacements. Concurrent or stale requests can overwrite scheduling based on an older snapshot.

Use one process-local scheduling coordinator with latest-revision semantics and a diff of pending identifier/content/trigger. Serialize its side effects, preserve the 60-request budget and today-completion suppression, and reconcile on time/day/permission changes. App and intent processes still need an authoritative storage revision; an in-process actor alone cannot coordinate separate processes. Await only required integration work in intents, and make any deferred work reliable within the extension/app execution budget rather than starting an untracked task which can be terminated.

`AppEnvironment.repository` creates a new repository each access. The app retains one, but widget providers and entity queries normally get fresh ones and lose the decode cache between calls. Reuse a safely shared instance per process, or load once per request and pass the snapshot through. Retain exact change detection/revision checks for writes from other processes. `BuddyEntry.selectedHabits` repeatedly sorts `data.active` while looking up each selected ID; prepare selected/by-ID habits once. Compact widget entries should carry only necessary render data after safe snapshot generation.

Every saved setting, note or check-in currently reloads all widget timelines and all controls. Route change categories to affected kinds; cosmetic app-only settings should not automatically trigger every widget and reminder. Keep a civil-day refresh policy. `MoreWidgets.nextRefresh` uses 86,400 seconds to find tomorrow; on a 25-hour local day that can select the same civil day and produce a past refresh date. Use Calendar day addition and verify fall-back DST/timezone transitions.

Timer clocks are already appropriately scoped. The separate risk is Finish: both app and Live Activity paths can read the same session, log it, and then clear it. The database lock serializes writes, but does not make that session claim idempotent; counted/measured time can be added twice if finish actions overlap. Use a unique session ID and an atomic completed-session token associated with logging, plus a common timer command coordinator. Test app/Live Activity finish overlap, cancel/finish overlap, starting a new timer during finish and relaunch recovery. This is a source-level race risk, not a reproduced device failure.

## Export memory and launch behavior

Year Review can render every habit into one tall bitmap. Weekly Recap likewise can grow with many rows. `ImageRenderer`, `pngData()` and file writing execute synchronously in the share handlers, with no rendering-in-progress state or duplicate-action guard. A nil-image error after attempting an oversized render is too late to manage its memory demand.

Estimate pixel count before allocating. Offer bounded pages/images or a paginated PDF for large datasets, and keep normal single-habit sharing unchanged. Compute summaries before entering the UI rendering step, show progress, disable a duplicate Share/Render action, and bound temporary outputs. Keep SwiftUI `ImageRenderer` construction/rendering on MainActor; move safe image encoding and file I/O to a worker through an explicitly thread-safe data/image pipeline. Do not send SwiftUI view state or arbitrary UIKit objects to detached tasks.

Launch currently registers eight bundled fonts and synchronously loads the repository in `AppStore.init`. First glyph access also reads/decodes both full icon catalogs. Profile cold launch to distinguish font registration, catalog decoding and disk/validation time. Separate a small prebuilt chrome lookup from the full picker search index, or prepare that index off-main before the picker needs it. Keep the same fonts, icons and licensed compatibility catalog. Render a lightweight loading/recovery state while storage is opening; do not briefly show onboarding or an empty account when existing data is still loading.

## Scaling examples, not runtime benchmarks

These are deterministic operation/memory estimates derived from the algorithms and dates. They do not measure Swift execution speed, disk speed or GPU allocation.

| Scenario | Work implied by current code |
|---|---|
| 100 habits, 100,000 records uniformly distributed by habit | Linear record-to-habit validation averages 5,050,000 ID comparisons; a dictionary needs approximately 100,000 lookups plus its 100-entry construction. Other validation remains. |
| 30 daily habits created 2016-10-03, viewed 2026-10-03 | One complete date pass contains 109,590 habit-days. Daily stats visits the histories twice; milestones adds another pass. A repeated body update repeats those calls. |
| One history starting 1970-01-01, viewed 2026-10-03, Monday week start | 20,730 civil days; the aligned heatmap has 2,962 week columns, 20,734 slots and a 38,506-point Canvas at 13-point pitch. Visible width covers a small fraction. |
| Pair analysis with the existing 30-habit cap | Up to 435 pairs, each creating several set operations. The current initializer still builds history sets for habits outside those candidates. |
| Illustrative 540 × 20,000-point export at scale 2 | 43.2 million pixels; one four-byte-per-pixel buffer is about 164.8 MiB before intermediate buffers and encoding. This height is an example, not a measured app image. |

## Implementation order

1. **Capture a Release baseline and add useful signposts.** Measure launch/load, transaction read/lock/validate/encode/write, tap-to-feedback, summary generation, Insights/search and export. Keep this instrumentation inexpensive.
2. **Fix the shared persistence path.** Dedicated ordered worker, latest-state command semantics, UI pending/error handling, ID-indexed validation, local settings drafts and encoded-size guard. Preserve durability and cross-process tests.
3. **Reduce repeated work.** Narrow display inputs and revisions; cache stats/streaks/milestones and screen summaries; replace synthetic aggregate databases with cells; prepare active/by-ID snapshots once.
4. **Bound scroll work.** Lazy growing lists, visible heatmap chunks, stable identities and prefetched cell data. Retain the reference geometry and access to older history.
5. **Make background results current.** Managed/cancellable Insights and notes search, composite pair IDs, reused pair computation and bounded allocation.
6. **Coordinate integrations and exports.** Notification diffs, selective widget/control reloads, reusable safe widget snapshots, idempotent timer finish and bounded image output.
7. **Polish interaction, then profile again.** Consistent pressed states/haptics, pending-save feedback, Reduce Motion, touch accuracy, preserved scroll position and measured GPU/layout refinements.

The highest-priority batch is steps 2–4. A wholesale persistence-framework migration or visual redesign is not needed to start improving the identified paths.

## Mac/iPhone verification plan

Profile a Release build on the oldest supported physical iPhone you intend to support and a ProMotion device. Repeat on the target iOS 27 SDK/runtime. Use Time Profiler and the SwiftUI instrument first; inspect long bodies and the cause-and-effect graph. Use Hangs/System Trace for file-lock or I/O stalls, Allocations for history/search/export, and energy tools for repeated reminder/widget work. Compare fixed workloads before and after each batch.

Test with synthetic, deterministic fixtures, not personal habit data:

| Dataset | Purpose |
|---|---|
| 10 habits / 90 days | Common short-history behavior and launch/check-in baseline |
| 30 habits / 5 years | Established user; daily/weekly/monthly/build/quit mix |
| 100 habits / 10 years, sparse records | History work independent of record count |
| 100,000 records, many notes, near the 64 MiB limit | Validation, load/write, search and memory scaling |
| 100 Dashboard widgets / large routines | Eager-vs-lazy scrolling and repeated member lookups |
| Backfill to 1970, many goal edits, pauses and freezes | Extreme history, cache invalidation and rule correctness |
| Large multi-habit exports | Pixel-budget enforcement and bounded peak memory |

Run cold/warm launch; rapid yes/no toggles and 20 counted taps; drag/reorder; switch layouts; fling cards/compact/Dashboard/history; open Explore/Milestones/Statistics; switch Insights ranges rapidly; type/delete notes search; save reminder text; finish timers from both surfaces; import/export; change theme/week start; foreground/background and midnight/DST/travel. Include VoiceOver, large Dynamic Type and Reduce Motion without sacrificing the reference's compact layout.

Record p50/p95 tap-to-feedback, main-thread busy intervals, visible-frame hitch rate, cold/warm launch, summary/search time, allocations/peak resident memory, bytes written and integration invocation counts. At 60 Hz the nominal frame interval is 16.67 ms; at 120 Hz it is 8.33 ms. The entire interval is not an application CPU budget. A proposed initial interaction target is p95 feedback below 50 ms on the agreed device, followed by a measured stricter target if feasible; this is a goal, not a current result or guarantee.

Add performance regression measurements for meaningful fixed workloads using XCTest metrics, plus ordering/cancellation/concurrent-write tests for the refactor. Existing tests provide strong domain coverage, including date arithmetic over 73,051 dates and concurrent repositories, but the UI fixture usually has ten habits and roughly 220 days. Its screenshot/interaction tests contain no performance metrics and bypass normal widget/reminder scheduling, so a green run cannot validate those integration costs.

## Primary platform references

The profiling and dependency recommendations follow Apple's guidance to measure Release builds, identify expensive body computations and restrict view dependencies. They are applied here to the specific source paths above; predicted app-specific bottlenecks remain inferences until traced.

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Optimize SwiftUI performance with Instruments, WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/)
- [Profile, fix, and verify: Improve app responsiveness with Instruments, WWDC26](https://developer.apple.com/videos/play/wwdc2026/268/)
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer), [initializer isolation](https://developer.apple.com/documentation/swiftui/imagerenderer/init(content:)) and [scale isolation](https://developer.apple.com/documentation/swiftui/imagerenderer/scale)
