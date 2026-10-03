# Visual evidence and second UI pass

Collected public App Store screenshots on 2026-10-03. `assets.json` records source URLs, hashes, download status and failure reasons. Assets remain research-only and are excluded from the app bundle.

The App Store screenshots cover progress, widgets, compact view, history, statistics and notes. The original website screens in `02_app_screenshots` remain the higher resolution reference for editor, detail, goals, share and month view. Versions and promotional layouts differ; the chosen geometry is documented in `docs/DESIGN.md`.

A public welcome screenshot from Appllama was inspected before the workspace interruption, but could not be downloaded again after restoration. Its page lists HabitKit 1.17.3 with 24 screens, 22 behind access controls. Those locked screens were not accessed. URL: https://appllama.io/apps/6443918070/habit-tracker-habitkit

Video located: https://www.youtube.com/watch?v=IA3vicKNYqc — Bill McLean comparison, HabitKit chapter roughly 1:55–4:46. The page/extractor loaded in the previous pass, but the media stream and storyboard previews returned a blocked/unavailable HTML response. No video was watched or valid frame recovered. Another listing, https://www.youtube.com/watch?v=8ZZkzr22t1g, was found but not verified. These are discovery links, not inspected video evidence.

The rebuilt native UI adds the reference palette, licensed searchable icon catalog, progressive editor, full history, notes, appearance overrides, a direct system share flow, and configurable widgets. UI tests capture real app screens using isolated synthetic habits. The fixture date is 2026-08-18; release builds ignore these environment options.

The final [Mac CI run](https://github.com/iyashwant/habbit-buddy/actions/runs/37114456851) passed 44 core tests, all four UI tests and the app/widget build on source `e28db103`. Its **17 real iPhone 17 / iOS 26.5 screenshots** are in `native_screens/`, with a contact sheet and per-image manifest. The gallery includes public references, paired comparisons and the full native batch. The comparison record documents what was observed and what remains uncertain. PNG originals are retained in the CI result bundle; checked-in images are JPEG quality 0.8. Native captures, unlike reference screenshots, show our implemented app.

A complete 1:1 match is not yet verified. Paywall/StoreKit, in-app language selection, alternate mode-conversion policies, exact year-review layouts and actual iOS 27 device behavior remain outstanding. See `docs/PARITY.md` and `docs/VALIDATION.md`.
