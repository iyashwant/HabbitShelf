# UI decisions

Reading this as a native daily habit tracker for a person checking in between activities, with HabitKit's compact dark contribution-grid language. The public app images are the visual authority. Design variance 2, motion intensity 2, visual density 7: preserve the established layout and quick interactions.

## Reference and tokens

Primary reference: the owner's own HabitKit dark-mode screenshots (cards, compact, detail, New Habit, Settings; 1179 × 2556, captured 2026-10-03), then `research/habitkit/02_app_screenshots/`. Tokens were sampled from those images after converting the two Display P3 captures to sRGB: canvas `#101013`, habit-card base `#1A1A1D` with a 5% habit-color tint fading out by 65% height, flat panels `#161619`, fields `#19191C`, round controls `#2B2B30` with a `#3B3B40` hairline, violet actions `#8B8AF8`, and the 21 Tailwind-400 habit colors. Empty tiles use 9% of the habit color inside the tracked range and 4.7% outside it (18% / 12% in the detail history). Light mode keeps the same structure on a `#F6F6F8` canvas with white cards.

Text uses bundled Figtree (SIL OFL), identified from the reference glyphs; dates, counts and small uppercase labels use SF Mono. Icons are bundled Lucide outlines (ISC), the reference's icon set; the chart, completion check, month-picker calendar and view-switcher glyphs are drawn from measured reference geometry where they differ from Lucide. Existing Font Awesome habit icons still render and remain searchable. Custom fonts scale with Dynamic Type, which rounds them to whole points, so a few labels use small tracking adjustments to keep reference widths. Contribution tiles carry progress, partial fill, today's outline and slip markers. Calendar cells offer explicit editing and accessible day labels; the heatmap is a summary rather than tiny tappable pixels.

The signature appears in card contribution grids, detail history, month mini-grids, share cards and home-screen widgets. Habit identity owns its color; global navigation and Save use violet. Navigation follows the reference's settings / statistics / plus toolbar and bottom three-view selector. Card rows have 14-point padding and 20-point corners; controls use smaller radii and primary actions use capsules.

## Component checkpoints

| Component | Intent and hierarchy | Surface and type | Spacing / states |
|---|---|---|---|
| Overview | Check in quickly; title and completion control lead the grid | Dark cards, native headline, muted description; per-habit accent | 16-point card inset; explicit empty state, error recovery, archive menu |
| Compact rows | Compare recent dates; name plus independent day controls | Shared day tile and habit icon; "Last N days" pill and uppercase SF Mono period | 52-point rows, 30-point tiles at a 38-point pitch; future and paused dates disabled, pre-start dates tappable for backfill; accessible amount/date labels |
| Editor | Name and identity first; progressive numeric/cadence controls | Native segmented pickers, text input, 21-color palette | Grouped 20-point screen inset; draft preserved on failed save |
| Calendar | Correct a date or add a note | Native month controls; outlined today; slip/check markers | Seven columns; system sheet and Cancel/Save |
| Statistics | Read totals, yearly history and monthly consistency | Two metric columns and native Charts; selected habit accent | Native scroll and selection; textual monthly alternative to chart |
| Sharing | Preview the image before sharing | Actual SwiftUI view rendered as PNG; theme/color controls | Native system share; errors stay visible; no simulated sharing success |
| Settings | Manage data and reminders deliberately | APP / HELP / ABOUT groups of 53-point rows with tinted icon tiles; each row opens a page | Theme page offers System / Light / Dark (new installs start dark); import validation before confirmation; recoverable replacement; denied-permission path |

## Skill application

Frontend Design: follow the concrete brief and deliberate hierarchy, rather than inventing a new aesthetic. UI/UX Pro Max: native SwiftUI accessibility search returned Dynamic Type, semantic views and descriptive labels; its broad design-system search initially suggested off-brief marketing/clay styling, so that output was discarded. The narrower retry supported flat mobile UI, but the supplied reference still controls palette and typography. Interface Design: reusable tokens, surface depth, explicit states and component checkpoints. Taste: brief inference, shape consistency and restrained motion; its native-mobile exclusion means web-specific typography/packages/hero rules do not apply here.

## Verification still required

Compare screenshots at the same iPhone width and text size. Check 375-point phone, landscape, largest Dynamic Type, VoiceOver and both themes. Compact cells intentionally follow the reference's dense visual size and need a device audit for touch accuracy. Exact icon library, fonts, card sizes, native transitions, share formats and notification presentation remain unverified against the installed reference app. No mocked native screenshots are presented as tested output.

## Second visual pass

App Store promotional screens are in `research/habitkit/07_visual_audit/references/`, with URL, byte count and checksum provenance. The editor uses an icon cloud, a separate searchable icon/emoji picker, and collapsed Advanced Options. Calendar dates use subdued tinted completions with a small dot; compact dates retain solid tiles. Full history scrolls horizontally and detail months scroll back to creation. Real simulator captures use debug-only isolated synthetic data dated 2026-08-18. They are generated by the UI test target; no design mockups count as validation.

## Third visual pass: owner screenshots

`HabitBuddy/Services/VisualSamples.swift` has a debug-only `reference` fixture that recreates the two habits in the owner's screenshots. Launch with `BUDDY_VISUAL_FIXTURE=reference`, `BUDDY_VISUAL_DATE=2026-10-03` and `BUDDY_VISUAL_HABIT=1` for the second habit's detail. Captures from a 393-point iPhone 15 Pro simulator were compared pixel by pixel with the reference images. Card frames, icon tiles, check buttons, every grid tile, compact rows, the detail history, chips, calendar card and month controls, the view switcher, editor fields and settings rows now land within 1–3 pixels (1 point or less) of the reference. Sheets sit about 9 points higher than in the reference because iOS 27 positions large sheets differently; their contents match relative to the sheet.

Intentional differences: no PRO button, FocusKit promotion, Language row or What's New row (no subscription, localization or release-notes feature); a Categories row and an ABOUT group cover existing features; streaks follow the engine's documented period rules, so the fixture shows 19 where the reference shows 18; Lucide's current cigarette and pulse glyphs differ slightly from the reference's versions. The owner's screenshots are personal and stay out of the repository.

## Dashboard, streak and year views

Added at the owner's request from five reference images of a light, pastel tracker (Today tiles and list, a widget board, yearly cards and a 12-month year page). Existing screens are unchanged; the new views use the same tokens, Figtree and SF symbols for flames and checks.

- Overview layouts **Streaks** (two-column tiles: streak count with unit, today's check, name, lettered week strip with done/7) and **List** (one row per habit) join Cards, Compact and Month in the view switcher. Both use the tinted style: pastel washes in light mode, tinted dark surfaces in dark mode.
- **Dashboard** opens from the overview toolbar (the reference's PRO slot). Small widgets take half a row and wide ones a full row, like the home screen. The pencil-style control edits order, removal and reset; plus adds a widget with a live preview, habit choice and Auto / Light / Dark / Tinted style. Tapping a widget opens its habit; the check logs today.
- **Year History** (one card per year, 21 days to a row, longest streak and completion) and **Year Calendar** (twelve month grids with stats, shareable as a PNG) open from the habit detail's options menu.
- Five home-screen widgets mirror the dashboard designs with interactive checks.

Verified on the simulator in both themes with the ten-habit sample fixture; home-screen placement of the new widgets still needs a device check.

## Explore pages

A compass button beside Dashboard opens **Explore**, a two-column grid of tinted cards, each with a live one-line summary: Insights, Calendar, Weekly Recap, Notes, Milestones, Routines and Timer. Each page uses the detail screen's back control and centered title, flat panels with uppercase captions, and the habit colors for data. Sentences lead each Insights section ("You're most consistent on Mondays (92%)"), with a chart beneath; within five points the weekdays are called even rather than ranking noise. The Calendar shades each day by the share of habits kept and shows a dot per completed habit; tapping a day opens a sheet of that day's habits with their checks, for logging or backfilling. The Weekly Recap is a poster like the Year Calendar, shareable as a PNG. Milestones are rings that fill toward each badge. Routines appear as chips above the overview only once one exists, so the overview is unchanged without them. Streak-frozen days use ice blue (`#7DD3FC`) with a snowflake on every grid. The timer is a large ring with SF Mono digits; its Live Activity uses the dark canvas with the habit's color for the clock and Finish button.
