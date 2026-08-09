# Session Log

Running record of what shipped, what's blocked, and what the next session should pick up. Newest session first.

---

## Session 1 — 2026-08-07 → 2026-08-08

### Where the project stands

**Shipped and on a physical iPhone via TestFlight internal testing.** App is named **Kyojin** (巨人). Bundle ID `com.mudit.logbook`, Team `YHK4D97KC4`. Build 1.0 (2) uploaded and installed.

Repo: <https://github.com/Mudit01100001/rerack> (public, MIT). Note the repo slug is still `rerack` from before the rename — cosmetic only, GitHub redirects if renamed later.

### Milestones complete

| Milestone | State |
|---|---|
| M1 — Skeleton, exercise library, cardio | ✅ built, verified on device |
| M2 — Routine builder | ✅ built |
| M3 — Active workout, ghost sets, live supersets | ✅ built |
| M4 — Drop sets | ✅ built |
| M5 — Rest timer + notifications | ✅ built |
| M6 — Live Activity | ⚠️ **designed only, NOT built** — see [`M6-live-activity-design.md`](M6-live-activity-design.md) |
| M7 — Finish flow + PR detection | ✅ built |
| M8 — Analytics & explainers | ❌ **not started** — 3 agent attempts stalled |
| M9–M11 | ❌ not started |

### 🔴 Top priority next session: external TestFlight distribution is blocked

**Symptom:** the "Friends" External Testing group cannot be attached to a build. Two symmetric failures, which together mean the group is not fully activated:

1. From the group side (**TestFlight → External Testing → Friends → Add Builds**): the build picker shows **"No builds available"**, even though build 1.0 (2) is uploaded, processed, and installed on a real device via internal testing.
2. From the build side (**Builds → iOS → 1.0 (2) → Group (+)**): the "Add Group to Build" modal lists **only the `internal` group**. "Friends" does not appear at all.

**State at end of session:** group "Friends" exists but reads `External Group • 0 Testers • 0 Builds`. Internal testing works perfectly — app is installed and running on the iPhone.

**What was tried:** filling in **What to Test** on the build's Test Information tab. Copy that was drafted for that field is in the section below, worth reusing.

**Important — do not repeat these guesses.** During the session I asserted, without being able to see the page, that an **"App Review Information"** section (name/phone/email) existed on the Test Information tab and was the likely blocker. **The user confirmed no such section is present.** Don't send them looking for it again.

**Suggested approach for next session — observe before advising:**
- Ask for a full screenshot/scroll of **TestFlight → Additional → Test Information** (the app-level page in the left sidebar, *distinct* from the per-build Test Information tab). Beta App Review contact details usually live at the app level, not the build level — that's the most likely real location and it was never actually inspected.
- Check whether **Beta App Review** has ever been submitted at all. External testing requires it; internal never does. This is the single most likely root cause: the group may simply be waiting on a submission that was never made, and Apple hides build attachment until then.
- Verify the build's own status string in **Builds → iOS** — confirm it says `Ready to Test` and not something export-compliance related lingering from build 1.0 (1).
- Consider the App Store Connect API as a way to read actual group/build state instead of guessing from screenshots.

**Note for whoever picks this up:** this whole stretch went slowly because I gave step-by-step instructions for UI I could not see, and several were wrong (device registration, the phantom App Review section). When the user says a described element isn't there, believe them immediately and ask what *is* on screen rather than proposing another guess.

### "What to Test" copy (drafted, reuse it)

```
Kyojin is a personal strength-training and cardio logbook — no accounts, no
subscription, everything stored on your device. Please try: creating a routine
and starting a workout from it, logging sets including supersets and drop sets,
using the rest timer, and logging a cardio session under the Cardio tab. Shake
your phone or use the screenshot button in TestFlight to send feedback anytime —
let me know what's confusing, broken, or missing.
```

### Also queued for next session

- **Crash reports / analytics** — user explicitly deferred this ("crash reports we'll do next session"). Start with TestFlight's built-in Analytics + Xcode Organizer Crashes panel (free, zero backend, no privacy tradeoff) before considering anything server-side. A usage-events database would contradict V1's stated zero-network promise (PRD §12.2) and deserves an explicit decision, not a quiet addition.
- **M8** — the one remaining milestone before the M1–M8 target is met. Three background agents stalled on it (infrastructure, not scoping). `Rerack/Persistence/ExerciseHistory.swift` was written as groundwork and is committed; the Exercise Detail screen, explainer system, and Profile dashboard are all still unbuilt.
- **M6 blockers** — the design doc found three pieces of existing state that live in SwiftUI `@State` and are invisible to a widget process: planned set count, rest state, and pending drop rows. Two are real bugs independent of M6 — **unticked drop rows are lost on relaunch**, which violates PRD Principle 4 ("never lose a set"). Worth fixing regardless of when the Live Activity gets built.

### Notable bugs found and fixed this session

Recorded because the pattern matters more than the individual fixes.

1. **Duplicate `SetLog` rows on re-tick.** `complete()`, `uncomplete()`, and `deleteExisting()` all indexed into a *completed-only* array by position. Re-ticking an un-ticked set inserted a second row and orphaned the first; un-ticking set 1 of 3 made set 2's values render in set 1's slot. All three now address rows by `orderIndex`. **Found by querying the SQLite store directly — the build was green and the UI looked correct.**
2. **Superset "No" didn't stick.** SwiftUI clears an alert's `isPresented` binding *before* running the tapped button's action, so the decline handler found its state already `nil` and never recorded the refusal — a declined pair could still be auto-grouped later. Pair identity now lives in state the binding doesn't touch.
3. **Superset auto-detect counted drop sets** as progress toward the expected set count, which could wrongly suppress a prompt.

**Lesson worth carrying forward:** a passing build and a correct-looking screenshot proved nothing in cases 1 and 3. Verify data-layer behaviour against the actual store:

```bash
find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data -name "Kyojin.sqlite"
# then: sqlite3 <path> "SELECT ZORDERINDEX, ZADDEDWEIGHTKG, ZREPS, ZISCOMPLETED FROM ZSETLOG;"
```

### Environment / workflow notes

- **The `.xcodeproj` is generated, never hand-edited.** Run `xcodegen generate` after any `project.yml` change or after cloning. It's gitignored on purpose.
- **If Xcode behaves oddly right after a `project.yml` change, fully quit and reopen it** — it can hold a stale in-memory copy of the project after an external tool rewrites the file on disk.
- Build headlessly: `xcodebuild -project Rerack.xcodeproj -scheme Rerack -destination 'generic/platform=iOS Simulator' build`
- The `appintentsmetadataprocessor: No AppIntents.framework dependency found` warning is **pre-existing and expected** — no AppIntents code exists until M6.
- Module sets `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. Any protocol a `@Model` conforms to must be `@MainActor` and must **not** inherit `Identifiable`.
- Export compliance is now answered in `Info.plist` (`ITSAppUsesNonExemptEncryption: false`), so uploads no longer prompt for it.
- **Bump `CURRENT_PROJECT_VERSION` in `project.yml` before every upload** or Apple rejects it as a duplicate. Currently at `2`.

### Open decisions carried forward

- **App icon variants.** Current icon is a single monochrome 巨人 on near-black. Full Dark/Tinted/Clear Liquid Glass variants need Apple's **Icon Composer** (GUI-only, not scriptable) — a manual pass whenever wanted.
- **Repo name** still `rerack`, app now `Kyojin`. Rename the GitHub repo if the mismatch becomes annoying.
- **PRD §23** logs verified-free assets for M11: [MuscleMap](https://github.com/melihcolpan/MuscleMap) (MIT, SwiftUI muscle highlighting) and [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain, 800+ exercises with instructions/images).
