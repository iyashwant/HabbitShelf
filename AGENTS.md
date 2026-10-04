# Habit Buddy working rules

Build a native SwiftUI iPhone app targeting iOS 26 and later (deployment target 26.0). The user's requested direction is a close visual and functional match to HabitKit, anchored to the public screenshots and docs in `research/habitkit/`. Keep the product name Habit Buddy and the repository name `habbit-buddy`.

Read `docs/DESIGN.md`, `docs/PARITY.md`, and `docs/ARCHITECTURE.md` before changing UI or domain behavior. These record actual decisions and outstanding verification. Do not silently reinterpret recorded local dates or historical goals. Use the shared engine for app, widget, and Shortcut writes. Keep imports transactional and preserve recoverable data.

The user explicitly requested these UI skills: **frontend-design**, **ui-ux-pro-max**, **design-taste-frontend** from Taste, and **interface-design**. Use their installed SKILL.md instructions when available; `scripts/install-design-skills.sh` installs project copies for a local Codex harness. The supplied HabitKit reference takes priority over suggestions to redesign, use different fonts, remove habitual cards, or switch to a web stack. Taste primarily covers web work; apply its brief-reading and consistency principles while using native Apple controls for this app.

Run `swift test` for domain/persistence changes and `python3 scripts/check-project.py` after project or research changes. On a Mac with Xcode 27, run `scripts/check-ios.sh`. Never claim Linux syntax checks prove an iOS build or that screenshot parity is verified without simulator/device evidence. If adding Swift files, regenerate the checked-in project with `python3 scripts/generate-project.py`.

Push requested changes to `dev` without force-pushing. Keep collected third-party images as research references; don't add them to the app's resource bundle. Do not add build outputs, credentials, signing certificates, personal export data, or Codex attribution footers.
