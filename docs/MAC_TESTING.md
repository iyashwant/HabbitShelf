# First Mac and iPhone check

Use Xcode 27 and an iOS 27 iPhone simulator. Run `bash scripts/check-ios.sh`. For physical widgets and Shortcuts, configure both targets with your team and the same App Group in `Config/Signing.xcconfig` / Signing & Capabilities.

1. Finish onboarding; create a yes/no habit and verify first tap completes, second clears, and relaunch preserves it.
2. Create a count habit with target 3; log 2, then 3, then 5. Check partial/full tiles, one qualifying day and saved over-goal total.
3. Create a measure habit with target 0.3; use Shortcuts to add 0.1 then 0.2. Check the precise total.
4. Backfill yesterday; add a note to a zero-progress day. Clear progress and confirm the note survives. Disable/re-enable notes and confirm they remain.
5. Change today's goal and check yesterday's result is unchanged. Convert build/quit and verify old scoring, today's cleared amount and retained note.
6. Exercise weekly 3 and monthly 20 schedules; compare streaks to the installed reference, including a short month and unfinished current period.
7. Exercise quit yes/no and numeric threshold 3; 2.999 is clean and 3 is a slip. Archive across a day boundary, restore, and verify archived dates are not inferred clean.
8. Switch all three overviews, week start and recent-day settings. Reorder and filter categories. Delete a category without deleting habits.
9. Review yearly/monthly/hourly statistics. Create/share PNGs in both themes and all four year-review formats. Try many habits.
10. Create multiple reminders, deny/grant notifications, complete or slip today, and inspect pending notifications and tomorrow's coverage. Check DST and travel; reopen after a week.
11. Add all widget families; choose a habit, tap rapidly, reopen app, remove/archive the configured habit, and cross midnight. Verify totals converge and fallbacks are clear.
12. Run all seven Shortcuts, including optional past date, note append, repeated complete above target, clear with note, archived habit and rejected future day.
13. Export/import valid data. Cancel both pickers. Reject corrupt, future-date and unsupported-version files. Restore a daily backup. The pre-restore file should be recoverable.
14. Compare reference and app screenshots on the same device width. Test small phone/landscape, large text, VoiceOver, light/dark, long titles and locale decimal input.

The 35 reference acceptance checks are also retained under `research/habitkit/06_ios_plan/acceptance_checks.txt`. Entries describing Pro transactions remain outside the implemented commerce scope.
