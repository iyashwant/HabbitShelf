# Habit Buddy

A native **iOS 27** habit tracker built in SwiftUI, with HabitKit's public screens and documented behavior as the reference. Work is on **`dev`**. Open **`HabitBuddy.xcodeproj`** in **Xcode 27** on your Mac.

Implemented: Card / Compact / Month overviews, contribution grids, calendar backfill, yes/no / count / measure tracking, build and quit modes, historical goal rules, daily / weekly / monthly streaks, notes, colors / icons / emoji, categories, ordering, statistics, local reminders, PNG sharing, year review, archive / restore, JSON import / export, automatic snapshots, four widget size/layout combinations, and seven Shortcut actions.

The app and widget extension passed an unsigned simulator build on GitHub's Mac runner. Exact screenshot parity and native behavior must be checked on iOS; see [the feature and verification matrix](docs/PARITY.md) for the remaining differences. The runner used Xcode 26.6 / iOS 26.5 SDK with a CI-only deployment override; iOS 27 remains the project target and needs Xcode 27 validation.

## Run on your Mac

```bash
git clone https://github.com/iyashwant/habbit-buddy.git
cd habbit-buddy
git switch dev
open HabitBuddy.xcodeproj
```

1. Install Xcode 27 and its iOS 27 simulator runtime.
2. Select the **HabitBuddy** scheme and an iPhone simulator, then Run.
3. For a physical iPhone, set your team and unique identifiers in [Config/Signing.xcconfig](Config/Signing.xcconfig). Enable the same App Group for **HabitBuddy** and **HabitBuddyWidgets** under Signing & Capabilities. A developer account supporting App Groups is needed for shared device storage.
4. Add widgets from the Home Screen's widget picker. Long-press the single-habit widget → Edit Widget → choose a habit. Shortcuts discovers the seven app actions after installation.

If App Group storage is unavailable, the app can use private local storage. Widgets show a setup message and write actions require the shared group. **Export data before changing bundle IDs or App Groups**, then import it into the new installation.

## Checks

```bash
swift test
python3 scripts/check-project.py
bash scripts/check-ios.sh  # Mac + Xcode 27
```

The standalone Swift package tests the actual engine used by the app and widgets. The current 43 core tests pass on the Mac runner; the original 41 also passed on Linux. [GitHub Actions run 37073838015](https://github.com/iyashwant/habbit-buddy/actions/runs/37073838015) also passed the project/research checks and built the app and widgets for both simulator architectures. See [the validation record](docs/VALIDATION.md) for SDK details and pending runtime checks.

## Project map

| Folder | Contents |
|---|---|
| `HabitBuddy/` | App entry, native screens, assets, settings and services |
| `Shared/Core/` | Civil dates, exact amounts, rules, streaks, storage, import validation, reminder plan |
| `Shared/Apple/` | App Group access, notifications and App Intents |
| `Shared/UI/` | Shared design tokens, icons, grid and day tiles |
| `Widgets/` | Interactive WidgetKit extension |
| `Tests/` | Domain and persistence tests |
| `UITests/` | Real simulator screen capture, persistence, validation and native sharing checks |
| `research/habitkit/` | Original 64-file research pack plus current App Store references, source audit and native comparison evidence |
| `docs/` | Architecture, UI decisions, feature status and Mac testing checklist |
| `scripts/` | Project generator, validation, Mac checks and UI-skill installer |

The second visual pass is in [research/habitkit/07_visual_audit/](research/habitkit/07_visual_audit/). Its [gallery](research/habitkit/07_visual_audit/gallery.html) contains the current public App Store screenshots.

Start the research at [research/habitkit/START_HERE.html](research/habitkit/START_HERE.html); open it locally for the linked galleries. Research images are excluded from app resources.

The requested UI skills were read and installed for this Codex session. Their source revisions are recorded in [docs/UI_SKILLS.json](docs/UI_SKILLS.json). To install them for your local Codex harness, run `bash scripts/install-design-skills.sh` with Node/npm available.
