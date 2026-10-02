# UI decisions

Reading this as a native daily habit tracker for a person checking in between activities, with HabitKit's compact dark contribution-grid language. The public app images are the visual authority. Design variance 2, motion intensity 2, visual density 7: preserve the established layout and quick interactions.

## Reference and tokens

Primary reference: `research/habitkit/02_app_screenshots/00_contact_sheet.jpg` and the eight `slide-*.webp` screens. Dark canvas `#0A0A0A`, card surface approximately `#1B1B1B`, subdued input surfaces, violet global actions approximately `#8F80F7`, mint `#29CDA0`, cyan `#27CBE4`, and yellow `#FFD32A` habit accents. Values are implementation approximations from the supplied images, not extracted native design tokens. Light mode uses white canvas and soft gray cards.

Use native SF typography and SF Symbols to match the iPhone density. Headline / body / caption hierarchy uses weight and secondary foreground. Numeric metrics use tabular figures. Contribution tiles carry progress, partial fill, today's outline and slip markers. Calendar cells offer explicit editing and accessible day labels; the heatmap is a summary rather than tiny tappable pixels.

The signature appears in card contribution grids, detail history, month mini-grids, share cards and home-screen widgets. Habit identity owns its color; global navigation and Save use violet. Navigation follows the reference's settings / statistics / plus toolbar and bottom three-view selector. Card rows have 16-point padding, approximately 22-point corners; controls use smaller radii and primary actions use capsules.

## Component checkpoints

| Component | Intent and hierarchy | Surface and type | Spacing / states |
|---|---|---|---|
| Overview | Check in quickly; title and completion control lead the grid | Dark cards, native headline, muted description; per-habit accent | 16-point card inset; explicit empty state, error recovery, archive menu |
| Compact rows | Compare recent dates; name plus independent day controls | Shared day tile and habit icon; caption labels | Dense reference layout; disabled pre-start dates; accessible amount/date labels |
| Editor | Name and identity first; progressive numeric/cadence controls | Native segmented pickers, text input, 21-color palette | Grouped 20-point screen inset; draft preserved on failed save |
| Calendar | Correct a date or add a note | Native month controls; outlined today; slip/check markers | Seven columns; system sheet and Cancel/Save |
| Statistics | Read totals, yearly history and monthly consistency | Two metric columns and native Charts; selected habit accent | Native scroll and selection; textual monthly alternative to chart |
| Sharing | Preview the image before sharing | Actual SwiftUI view rendered as PNG; theme/color controls | Native system share; errors stay visible; no simulated sharing success |
| Settings | Manage data and reminders deliberately | Native Form and labeled controls | Import validation before confirmation; recoverable replacement; denied-permission path |

## Skill application

Frontend Design: follow the concrete brief and deliberate hierarchy, rather than inventing a new aesthetic. UI/UX Pro Max: native SwiftUI accessibility search returned Dynamic Type, semantic views and descriptive labels; its broad design-system search initially suggested off-brief marketing/clay styling, so that output was discarded. The narrower retry supported flat mobile UI, but the supplied reference still controls palette and typography. Interface Design: reusable tokens, surface depth, explicit states and component checkpoints. Taste: brief inference, shape consistency and restrained motion; its native-mobile exclusion means web-specific typography/packages/hero rules do not apply here.

## Verification still required

Compare screenshots at the same iPhone width and text size. Check 375-point phone, landscape, largest Dynamic Type, VoiceOver and both themes. Compact cells intentionally follow the reference's dense visual size and need a device audit for touch accuracy. Exact icon library, fonts, card sizes, native transitions, share formats and notification presentation remain unverified against the installed reference app. No mocked native screenshots are presented as tested output.
