# Kyojin 巨人

A free, local-first iOS strength-training and cardio logbook. No accounts, no subscription, no server in V1 — your data lives on your phone.

Full product spec: [`PRD.md`](PRD.md) · Session history and current blockers: [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md).

> The repo slug is still `rerack` from an earlier working name — cosmetic only. The app is **Kyojin**. The Xcode target is also still named `Rerack` internally, which is why build commands below say `Rerack.xcodeproj`; only `CFBundleDisplayName` is user-facing.

## Status

**V1 feature-complete, build 5.** Every milestone M1–M11 is built. Drop sets and swipe-to-delete were unreachable at runtime for the whole of V1 and were fixed on 2026-08-18; a first round of on-device feedback (scrolling, the Live Activity, haptics, onboarding, swipe visuals) landed on 2026-08-19. All verified end to end against the SQLite store or on the simulator — see [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md) Sessions 3–5.

| Milestone | State |
|---|---|
| M1 — Skeleton, exercise library, cardio | ✅ |
| M2 — Split builder | ✅ |
| M3 — Active workout, ghost sets, supersets | ✅ |
| M4 — Drop sets | ✅ |
| M5 — Rest timer + notifications | ✅ |
| M6 — Live Activity + Dynamic Island | ✅ ([design doc](docs/M6-live-activity-design.md)) |
| M7 — Finish flow + personal records | ✅ |
| M8 — Analytics & explainers | ✅ |
| M9 — CSV export, Apple Health sync | ✅ |
| M10 — Share cards, animal ladder, Instagram Stories | ✅ |
| M11 — Onboarding, accessibility, units, widgets | ✅ |

Beyond the milestone list: home-screen widgets, split templates, a plate calculator, and kg/lb units.

Cardio-console OCR shipped in V1 and was **removed** on 2026-08-18 after testing against three real machines: Vision cannot read seven-segment displays, and on the one console where it read anything it returned `65:00` as `0959` at full confidence. The measurements are in [PRD §22.1](PRD.md#221-reading-a-console-photo--the-vision-framework--abandoned-2026-08-18).

Row gestures do not use `.swipeActions` — SwiftUI honours it on `List` rows only, and this screen is a `ScrollView` of cards. [`SwipeActionRow`](Rerack/App/SwipeActionRow.swift) reimplements the interaction with a single gesture recognizer shared by every row (a hub, not one per row — that per-row version was the cause of build 4's scroll jank), so a swipe begun on a text field still works and the list stays smooth in a long workout. The workout screen itself is a system `.sheet`, not a hand-rolled dismiss gesture, so scroll and dismiss can't fight each other.

Two batches of UX fixes from full-workout tests have landed — see the [session log](docs/SESSION-LOG.md) Sessions 4–5 for the exact split of what shipped versus what's still open. A tuning surface for how the app's haptics feel lives at Profile → Developer → Haptics Lab, since that can only be judged on a real device.

Two further things are deliberately outstanding rather than unfinished — artwork, which needs files rather than code ([`docs/ARTWORK.md`](docs/ARTWORK.md)), and Apple Calendar sync, which is an open product decision. Both are tracked in the [session log](docs/SESSION-LOG.md).

See the [Build Order](PRD.md#16-build-order--testflight-expectations) in the PRD for what each milestone covers.

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Setup

```bash
git clone https://github.com/Mudit01100001/rerack.git
cd rerack
xcodegen generate
open Rerack.xcodeproj
```

Build and run on any iOS 17+ simulator or device.

### Why there's no `.xcodeproj` in the repo

The Xcode project is generated from [`project.yml`](project.yml) by XcodeGen. `project.yml` is the source of truth and the only one tracked in git — the raw `.xcodeproj`/`project.pbxproj` format is internal, auto-managed, and produces brutal, unreadable merge conflicts if two people (or two AI sessions) touch it at once. Run `xcodegen generate` any time you pull a change to `project.yml`, or after cloning.

## Architecture

- **SwiftUI + SwiftData**, iOS 17+ minimum deployment target
- No third-party dependencies
- No network calls of any kind in V1 — fully offline
- Two targets: the app, and `RerackWidget` for the Live Activity and home-screen widgets. They share the SwiftData store through an App Group (`group.com.mudit.logbook`) and the code in [`Shared/`](Shared)
- Weights are stored in kilograms everywhere — the model, the CSV, the HealthKit bridge. Pounds are a display conversion applied at the edge ([`Shared/Weight.swift`](Shared/Weight.swift)), so switching units never rewrites a row

## Distribution

TestFlight setup — including the steps that need your own Apple Developer credentials — is documented in [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

Bump `CURRENT_PROJECT_VERSION` in `project.yml` before every upload, or App Store Connect rejects the build as a duplicate.

## Contributing

This is a personal project built in the open. Issues and PRs are welcome, but the roadmap and product decisions are driven by the PRD — read it first if you're proposing a feature rather than a bug fix.

## License

[MIT](LICENSE).
