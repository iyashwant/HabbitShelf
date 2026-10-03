# HabitKit feature and verification status

The requested target is a 1:1 match to HabitKit on iOS 27. This matrix separates implemented code from parity that still requires device/reference evidence. The reference app's source code and private data format are unavailable; public documentation is collected in `research/habitkit/`.

| Feature area | Implemented | Remaining parity or native checks |
|---|---|---|
| Offline setup | No account; onboarding; optional clearly labeled sample habits | Compare first-run copy and flow |
| Habit editor | Name, description, 1,407 free Font Awesome icons/emoji, 21 colors, build/quit, all tracking modes, cadence, categories, up to 3 reminders | Searchable catalog and full-grapheme custom emoji; precise icon style still needs comparison |
| Yes/no / counts / measures | One-tap toggle, increment, total editor, exact 3 decimals, over-goal values, past-date correction | Compare keyboard and editor presentation |
| Historical goals | Dated target/mode/tracking rules; edits effective today | Reference conversion carry-over / alternative clear-history policies are not reproduced |
| Streaks | Daily / weekly / monthly; no goal; unfinished-today grace; current period reachability | Partial-period, target-edit and aggregate semantics are defined in ARCHITECTURE.md where docs are incomplete |
| Quit | Clean days derived; slips; strict numeric threshold; historical mode meaning | Advanced conversion policies and locked clean-history carry-over need reference testing |
| Notes | Note-only, append/replace in Shortcuts, preserve on clear, setting hides without deleting | Dedicated newest-first notes list and calendar long press; compare interactions on device |
| Overview | Cards, Compact 1–7 recent days, three-column/adaptive Month, reorder/category filter, numeric progress rings, yesterday complete/clear commands, global and per-habit card appearance switches, filter/switcher/name/drag settings | Pixel comparison and calendar headers still pending |
| Grids/calendar | Civil dates, future/pre-start/paused states, partial fill, today outline, selected week start, month navigation | Full scrollable contribution history and months through habit creation; native geometry comparison pending |
| Categories/archive | Multiple memberships, create/delete category, reorder habits, archive/restore, paused intervals, explicit delete | Editable category names and icons; native interaction comparison pending |
| Statistics | Habit/year selection, yearly grid, completions, rate, monthly area chart, current/best streak, completion-hour chart | Exact denominator/aggregate formulas need reference comparison; current formula documented |
| Habit sharing | PNG rendering, theme/color, description, streak, completion indicator, native share | Confirm image dimensions and precise reference layout |
| Year review | Multiple habit PNG with Cards / Compact / Grid / Poster formats | Format geometry is an approximation; exports with many habits need memory/device testing |
| Local reminders | Up to 3 per habit, weekdays/time, global check-in, permission denial, completion suppression, measurable 60-request queue | Native delivery, DST/travel/restart and many-habit queue test; reference background scheduling may differ |
| Widgets | Small/medium single habit and medium/large compact (3/8 habits, 10/11 days); app intents and deep links | App Group signing, rapid tapping and midnight refresh need device test; single and multi-habit selection plus System / Light / Dark options; native widget placement pending |
| Shortcuts | Complete, clear, increment, log amount, log note, get progress, open habit | Siri parameter discovery and execution need iOS 27 validation; progress is a JSON string rather than typed output fields |
| Recovery | 7 daily snapshots, 3 before-restore snapshots, manual versioned JSON export/import, corruption recovery | Mac/iPhone file picker, protection and app-kill behavior; HabitKit proprietary imports intentionally unsupported |
| Settings | System/light/dark, first weekday, today outline, recent-day count, notes/haptics and card visibility switches | In-app language selection and full localization not implemented |
| Pro / StoreKit | All implemented features currently available for development/testing | Reference free-4 limit, purchase paywall/subscriptions/lifetime/restore are not implemented; require your product IDs and commercial setup |
| Branding | Habit Buddy name and its own app icon; licensed Font Awesome habit icons and native SF navigation symbols | Reference HabitKit branding/assets remain research-only |

The app has not been claimed as a verified complete 1:1 clone. To reach that bar, compile with Xcode 27, exercise the paired reference app, compare screenshots, and close the differences above. Core checks and build results are recorded in `docs/VALIDATION.md`.
