# Kyojin 巨人

A free, local-first iOS strength-training and cardio logbook. No accounts, no subscription, no server in V1 — your data lives on your phone.

Full product spec: [`PRD.md`](PRD.md) · Session history and current blockers: [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md).

> The repo slug is still `rerack` from an earlier working name — cosmetic only. The app is **Kyojin**. The Xcode target is also still named `Rerack` internally, which is why build commands below say `Rerack.xcodeproj`; only `CFBundleDisplayName` is user-facing.

## Status

**V1 feature-complete.** Every milestone M1–M11 is built and verified on a physical device via TestFlight internal testing.

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

Beyond the milestone list: home-screen widgets, cardio-console OCR, split templates, a plate calculator, and kg/lb units.

Two things are deliberately outstanding rather than unfinished — artwork, which needs files rather than code ([`docs/ARTWORK.md`](docs/ARTWORK.md)), and Apple Calendar sync, which is an open product decision. Both are tracked in the [session log](docs/SESSION-LOG.md).

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
