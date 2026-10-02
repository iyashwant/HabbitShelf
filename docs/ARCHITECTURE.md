# Architecture and data behavior

Native SwiftUI app and WidgetKit extension targeting iOS 27. No backend, login, external runtime package, analytics or remote habit storage. `Package.swift` compiles the same Foundation-only core files separately for tests. The Xcode targets compile these shared files directly, so runtime writes and tests use the same implementation.

## Storage

`habits-v1.json` in the App Group contains a versioned Codable snapshot. Every write opens an advisory process lock, reloads the latest snapshot, applies the mutation, validates all invariants, and atomically replaces the file. Independent repository instances are tested with 30 concurrent increments. Failed validation leaves the committed file unchanged. This JSON repository was selected over the earlier research proposal's SwiftData adapter to share one transactional write path with widget processes and to test recovery on Linux.

Up to seven dated snapshots are retained, captured before the first write on each used day. Up to three before-restore snapshots are also retained. Import is replace-only: decode and validate first, confirm in UI, preserve the original bytes, then atomically commit. A corrupt primary file can be explicitly recovered from a valid export. Unknown schema versions are rejected; migrations must be added before increasing the schema. Portable exports include settings as well as habits and records.

App Group identifiers are configured in `Config/Signing.xcconfig` and expanded into both targets' Info.plist and entitlements. The app's private-storage fallback supports simulator/development configurations lacking the group. Widget actions require shared storage rather than silently writing into an unrelated extension file. Changing the group requires exporting/importing data.

## Dates and precision

Civil `YYYY-MM-DD` keys are created in the current local time zone and never recomputed from timestamps. UTC Gregorian arithmetic operates on those civil keys, avoiding DST day-length assumptions. Counts are whole numbers. Measured totals store integer thousandths, with a nonnegative maximum of one billion units. Timestamps use whole seconds; the completion's local hour is saved independently for the time chart. Backfilled completions record the time they were entered.

Goal versions are ordered by effective date. Edits start today; repeated edits today replace today's version. Build/quit and tracking changes preserve old rule versions and reset today's amount while preserving its note. Amount editing in a previous mode is locked; note editing remains available. A restored archive records paused dates, so quit histories don't gain clean days during the archived interval.

## Scoring

Build success: amount >= historical target. Quit success: amount < historical threshold, with unlogged clean days derived only within tracked periods. Yes/no thresholds are one. Over-goal totals remain stored and qualify once. Complete is idempotent; clear preserves the note. Future, pre-start, paused and archived writes are rejected.

Daily unfinished today doesn't break yesterday's streak; a missed past day does. None disables streak tracking. Weekly/monthly streaks count successful dates, not successful periods. Completed periods must meet their target; an unfinished period carries the previous streak while its target remains reachable. A period's target is capped to its tracked segment length, including short months and a partial first period. Goal versions split cadence periods at the effective day; changes to cadence or mode start a new streak segment. These boundary choices are explicit where the reference docs don't define exact behavior.

Completion rate counts eligible build dates through yesterday plus today if completed. Quit dates and archived pauses are excluded. Aggregate current/best streak is the maximum across selected habits; it is not a combined all-habits streak. Monthly/year totals count distinct successful habit-days. Time-of-day counts saved completion hours for qualifying build dates.

## Notifications and automation

One-off local notifications cover a rolling seven-day window, with 60 earliest requests reserved below the system's pending-request limit. The UI reports omitted requests. Launch, logging and settings changes refresh the schedule. Today is suppressed after build success or quit failure. Settings permission denial preserves reminders and offers a system-settings link. Travel and DST are handled using local calendar components; continuous background rescheduling while the app is never opened is not guaranteed.

Widgets request periodic/midnight refreshes and use the same repository and engine for writes. All seven Shortcut actions are defined in `HabitIntents.swift`. Get Progress returns JSON with exact amount strings, goal, remaining, unit, note and success. Numeric totals needing an editor should open the app; no keyboard runs inside a widget. Widgets and Siri execution still need real iPhone validation. Retrying a non-idempotent increment as a separate invocation intentionally adds another increment.

## Project maintenance

`scripts/generate-project.py` deterministically emits the checked-in app/widget project and shared scheme. It has no external dependency. `check-project.py` checks source membership, plist validity, research hashes and gallery links. Research folders are not app resources. UI styling lives in shared tokens rather than copied screenshot raster assets.
