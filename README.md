# Rerack *(working name)*

A free, local-first iOS strength-training and cardio logbook. No accounts, no subscription, no server in V1 — your data lives on your phone.

Full product spec: [`PRD.md`](PRD.md).

> `Rerack` is a working name, not final — see [Appendix A](PRD.md#appendix-a--app-identity--shipping-name) of the PRD for how the name stays swappable and the shortlist of alternates.

## Status

Actively in development. Currently: M1 (exercise library, cardio manual entry) is done; M2 (routines) is in progress. See the [Build Order](PRD.md#16-build-order--testflight-expectations) in the PRD for the full milestone list.

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
- Data lives in an App Group container from day one, so a future Live Activity / widget extension (see PRD §8) can share the same store without a migration

## Contributing

This is a personal project built in the open. Issues and PRs are welcome, but the roadmap and product decisions are driven by the PRD — read it first if you're proposing a feature rather than a bug fix.

## License

[MIT](LICENSE).
