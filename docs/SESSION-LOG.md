# Session Log

Running record of what shipped, what's blocked, and what the next session should pick up. Newest session first.

---

## Session 4 — 2026-08-18

### The drop-set bug is fixed, and the fix is verified end to end

Session 3 found that `+ Drop` and swipe-to-delete were unreachable: both were declared with `.swipeActions`, which SwiftUI honours on `List` rows only, while the active workout screen is a `ScrollView` of cards.

**`List` was rejected, and the reasoning in Session 3 was wrong about why.** A `List` with `.listStyle(.plain)`, hidden separators, clear row backgrounds and zero insets renders identically to the current cards — the "plain text look" is the *default* styling, not a property of `List`. The real blocker is structural: drop rows must be independently swipeable while sharing their parent's alternating band, and a flat list of rows cannot express that nesting.

So the interaction was reimplemented in [`SwipeActionRow.swift`](../Rerack/App/SwipeActionRow.swift): finger-tracking with rubber-banding, a detent haptic at the commit threshold, full-swipe, one-open-row-at-a-time, and VoiceOver actions (a bare gesture is invisible to the screen reader, so fixing a bug would otherwise have broken §17).

**A SwiftUI `DragGesture` was not enough, and finding out cost a full build cycle.** With the gesture attached in SwiftUI the swipe fired from the set-number column and did nothing when begun on the kg or reps field — which is most of the row's width. The fields' own UIKit recognizers win the gesture arena before a parent `simultaneousGesture` sees the touch. The working version installs a `UIPanGestureRecognizer` on the enclosing scroll view and gates it in `gestureRecognizerShouldBegin` to "decisively horizontal, and inside my bounds." Vertical scrolling and taps into the fields are both untouched.

**Verified on the simulator, then against the store:**

| Step | Result |
|---|---|
| Swipe from a text field | Drop + Delete revealed |
| Tap Drop | Row `↳ D` at 20 kg (24 − 20%, rounded to 2.5) |
| Store after ticking | `20.0 / 8 / drop / has_parent = 1` |
| Volume | 448 = 288 + 160 — drops count fully (§7.9) |
| Rest after ticking parent | **Suppressed** — chain still open, the two-gate rule |
| Next session, tick set 1 | `↳ D` materialises with Previous `20×8` |

Every one of those paths had been written and none had ever run. `···` now also carries **Add Drop Set to Last Set** and **Delete Last Set** as permanent failsafes — a swipe is invisible until you know it exists.

### Haptics

The app contained exactly one haptic call. [`Haptics.swift`](../Rerack/App/Haptics.swift) adds a vocabulary: light taps for ticks, a firmer one for deletes, a detent on swipe threshold, selection ticks while scrubbing, and three genuine Core Haptics *patterns* — a rising two-tap chime when rest ends (the one moment the app speaks first, so the only ascending pattern), an ascending swell for a PR, and a decaying burst matched to the confetti's fall rather than one thump at the top.

Generators are cached and pre-warmed at launch: a cold Taptic Engine lands the first tap tens of milliseconds late, which made the first set of a workout feel unresponsive while every later one felt fine.

### Fixes from the full-workout test

| # | Item | State |
|---|---|---|
| 2 | Swipe left to delete, right to add a set carrying the same values; every add-set path now inherits this session's last entry | ✅ built |
| 3 | Press-and-hold a kg/reps field, drag to scrub, value floats above the field | ✅ built, not gesture-tested |
| 4 | Scroll no longer throws the session away | ✅ verified |
| 5 | Lock Screen decluttered; rest bar **drains** instead of filling | ✅ built |
| 6 | Lock Screen ground is translucent black, not grey | ✅ built |
| 8 | Swipe the list to dismiss the keyboard | ✅ built |
| 12 | Save-to-Photos alert → calm top toast | ✅ built |
| 14 | Consistency widget spans full width, day letters added | ✅ built |
| 15 | Day letters on the Home consistency grid | ✅ verified |

**Item 4's cause is worth recording.** An unconditional `simultaneousGesture` dismissed on *any* downward drag over 90pt. A scroll and a dismiss are the same finger movement; the only thing separating them is whether there is anything left to scroll. Two gates now: at the top of the list, **and** the drag began in the upper third. A visible grab pill replaces what was an invisible gesture nobody could find and everybody triggered.

**Item 5's progress bar was a real inversion.** `ProgressView(countsDown: false)` filled left-to-right, so a *full* bar meant rest was **over** — the opposite of the intuition for a countdown.

### 🔴 Not done — carried to next session

Honest list. These were asked for in the same pass and are not built:

1. **Item 1** — workout tile should open an exercise panel with its own Start Workout, separate from the Start button.
2. **Item 9** — slider instead of ±15s in-app (Live Activity keeps the buttons).
3. **Item 10** — the header clock shows total time during rest, which is what makes rest vs. workout state ambiguous.
4. **Item 11** — on finishing a diverged template: "Save as new workout" / "Keep the old workout". Note the second half of that request (weights carrying across workouts) is a **separate concept** and may already work via §7.3 ghost priority 1 — check before building.
5. **Item 13** — widget rework. **WidgetKit cannot scroll at any size**, so the shippable shape is the constrained one: current workout, a tick button, tap-through.
6. **Cardio console rebuild** — remove the draw-a-box flow, remove the contradictory "Attach a photo / auto-reading isn't built yet" caption ([`AddCardioSessionView.swift:93`](../Rerack/Features/Cardio/AddCardioSessionView.swift), now false), and replace with label-proximity parsing over whole-frame OCR. **Blocked on a console photo** to tune against. `DataScannerViewController` (VisionKit, iOS 16+) is the API behind Live Text and is the right surface. Foundation Models is **text-only** — useful for turning OCR strings into structured fields, useless for reading pixels.
7. **Onboarding** — the swipe gestures from item 2 need a slide, since a swipe nobody knows about is the same as no swipe.

### Still true from Session 3

TestFlight build 3 archived but never uploaded; external testing likely blocked on a Beta App Review submission that was never made. Artwork still needs files, not code.

---

## Session 3 — 2026-08-14

### Drop sets cannot be created. The feature is unreachable, not merely incomplete.

Session 2 listed "ghost sets don't reproduce a drop chain" as deferred. That specific gap **was already closed** in `6b0ca8a` — `GhostSet.drops` carries the chain, and `ExerciseCardView.materialiseGhostDrops` writes it back as real un-ticked rows when the parent is ticked. The doc was stale.

Verifying it on the simulator turned up something worse. **`+ Drop` has no reachable entry point:**

- Both `addDrop` call sites reach the user only through `SetRowView`'s `.swipeActions(edge: .trailing)`.
- SwiftUI honours `.swipeActions` on `List` rows only. The active workout screen is a `ScrollView` → `VStack` of cards ([ActiveWorkoutView.swift:97](../Rerack/Features/ActiveWorkout/ActiveWorkoutView.swift:97), [ExerciseCardView.swift:214](../Rerack/Features/ActiveWorkout/ExerciseCardView.swift:214)). The modifier is inert.
- PRD §7.4 promises `···` → "Add drop set to last set". That entry was never built.

So there is no gesture and no menu item. **No drop set can be created, therefore no chain can ever be logged, rendered, exported, or reproduced.** Everything downstream of creation — the −20% pre-fill, the two-gate rest rule, the PR maths in §13.4, the `set_type = drop` CSV columns, the ghost reproduction — has never run against real data.

**The same dead modifier also carries `Delete`.** A logged set cannot be removed from the active workout screen, and the `Set deleted · UNDO` toast in §7.3 has never appeared. Full-swipe-to-complete (§7.3) was never implemented in either direction.

**How it was verified.** Fresh install, Quick Start, Alternate Hammer Curl, 20 kg × 10, ticked. Three separate trailing-swipe attempts on the completed row — a fast `swipe`, then two slow multi-point `touch_path` drags from different x origins — revealed nothing. The `···` menu was opened and screenshotted: Set Rest Timer, Plate Calculator, Add to Superset, Remove Exercise, and nothing else. Store confirmed the negative:

```
ZORDERINDEX  ZADDEDWEIGHTKG  ZREPS  ZISCOMPLETED  ZSETTYPERAW  has_parent
0            20.0            10     1             normal       0
```

**Why nobody caught it.** A green build and a correct-looking set row prove nothing about a gesture that silently does nothing — there is no error, no log line, and the row renders exactly as designed. This is the third time on this project that reading the code and reading the screen both agreed while the actual behaviour differed; the store and the gesture had to be exercised directly.

**Not fixed — it needs a design decision.** Moving the set list into a `List` to make `.swipeActions` live would forfeit the card layout, the alternating row banding and the concentric radii. The cheaper routes are a custom `DragGesture` on the row, or adding the missing `···` entries. Left for the next session rather than picked unilaterally.

### Docs corrected this session

- [PRD §7.3](../PRD.md) — note that no swipe gesture works
- [PRD §7.4](../PRD.md) — what the `···` menu actually contains
- [PRD §7.9](../PRD.md) — the chain is unreachable; ghost reproduction itself is done
- [PRD §16.2](../PRD.md) — M3 and M4 downgraded from ✅ to ⚠️
- Session 2's item 5 below is superseded by this entry

---

## Session 2 — 2026-08-14

### Where the project stands

**V1 is feature-complete.** M6 and M8–M11 all shipped this session, closing every milestone in the PRD build order. Seventeen commits. The build is green and every feature below was exercised on the simulator or a physical device before being called done.

Version is at `1.0 (3)` in `project.yml`. Build 3 was archived successfully but **not uploaded** — that's the one mechanical thing left over.

### What shipped

| Area | Detail |
|---|---|
| **M6 — Live Activity** | Lock Screen + all four Dynamic Island layouts. `LiveActivityIntent` ticks a set without unlocking, ±15s and skip on the rest phase. Verified on device. |
| **M8 — Analytics** | Exercise detail (Summary/History/How To), Swift Charts progress, PR cards, profile dashboard, all 13 explainer entries. |
| **M9 — Data** | CSV export, HealthKit read (bodyweight, body fat) and write (workouts). |
| **M10 — Share** | Four card styles, animal ladder, Instagram Stories hand-off, confetti, save to Photos. |
| **M11 — Polish** | Onboarding, dominant hand, accessibility pass, units. |
| **Home-screen widgets** | Day-wise split selector (deep-links straight into a workout) and a streak + contribution grid. |
| **Cardio OCR** | Vision-based console scanner with a preprocessing pipeline. Never auto-submits — see below. |
| **Splits & templates** | Five importable templates including the user's own PPL. 42 exercise references verified against the catalogue. |
| **Units** | kg/lb throughout. **Kilograms remain the storage unit permanently** — every `…Kg` property, `_kg` CSV column and Health bridge stays metric; pounds are a display conversion at the edge in [`Shared/Weight.swift`](../Shared/Weight.swift). Round-trip drift measured at zero. |
| **Design system** | [`DesignSystem.swift`](../Rerack/App/DesignSystem.swift) — golden-ratio type scale, 4pt spacing, concentric radii via `Outer R = Inner R + Padding`. |

**Terminology is now split > workout > exercise.** The word "routine" appears in no user-facing string. Type names still say `Routine` internally; renaming them is a mechanical refactor nobody has needed yet.

### 🔴 What's actually left

**1. Design tweaks — Instagram card, Dynamic Island, widgets.** All three work on device; the user reports they need visual refinement but hasn't specified what. **Get screenshots before changing anything.** Every time this session a visual issue was fixed by reasoning rather than looking, the wrong element got changed — the clearest case being a request to change button corner radii that turned into rebuilding the container. Ask what's on screen; don't infer it.

**2. Artwork — blocked on files, not code.** The user is making it. All plumbing is done and documented in [`ARTWORK.md`](ARTWORK.md), with every expected filename in [`artwork-manifest.txt`](artwork-manifest.txt). Drop-in works with no code change.

  A real bug was found and fixed while writing that doc: artwork must live in **`Shared/Artwork.xcassets`**, not `Rerack/Assets.xcassets`. The Live Activity runs in a separate process that can only read its own bundle, so anything in the app's catalogue would have been invisible to it — the Lock Screen thumbnail would have stayed a glyph forever with no error to explain why. Verified by `assetutil`-ing both compiled `Assets.car` files.

**3. Apple Calendar — an open decision, not a task.** Nothing is built; there is no EventKit code in the repo. The proposal was: a dedicated app-owned calendar with recurring all-day events per split day, so removing the sync deletes only our events. Owning the calendar is the whole safety argument. The user said "idk how to test" — worth knowing the Simulator has a working Calendar app, so this is verifiable end-to-end without a device. Google Calendar stays out: OAuth plus a network round-trip would break §12.2's offline promise, and adding a Google account to Apple Calendar gets the same result for free.

**4. TestFlight build 3 upload.** Archive succeeded; upload never happened. External testing additionally needs a **privacy policy URL** because the app touches HealthKit. Session 1's external-group blocker (below) was never resolved and may still bite.

**5. Deferred and still deferred.** ~~Ghost sets don't reproduce a drop chain into the next session (PRD §7.9) — needs a ghost-format change.~~ **Superseded by Session 3** — that gap was already closed in `6b0ca8a`; the real problem is that drop sets can't be created at all. Crash reporting is still untouched; start with TestFlight Analytics and the Xcode Organizer before anything server-side.

### Bugs worth remembering

**Data loss, found by accident.** Routine self-heal ran `templates[completed.count...]`. For an exercise with *zero* completed sets that expression deletes **all** targets — so skipping one exercise permanently wiped its plan and gutted imported templates. Fixed by guarding `if !completed.isEmpty, templates.count > completed.count`. It was found while testing confetti, not by any test. A range expression whose lower bound comes from a count is worth a second look every single time.

**Un-ticked drop rows vanished on relaunch** — the Session 1 carry-over that violated Principle 4. Fixed by persisting drop rows at creation.

**Confetti took three attempts,** and the two failures are both instructive:
- `TimelineView(.animation(paused:))` captures its schedule at build time and never restarts.
- Animating a `progress` value with `withAnimation` interpolates the *endpoint* modifier values, so opacity computed to 0 at both ends and every piece fell fully transparent.

  The fix was `TimelineView(.animation)` + `Canvas` for genuine per-frame evaluation. Verified by temporarily stretching the duration to 20s, screenshotting mid-fall, then restoring 3.4s — a trick worth reusing on any animation that "does nothing".

**Environment keys don't cross `fullScreenCover` reliably.** Dominant hand was saved correctly in SQLite but never reached the set rows. Re-inject `.environment(...)` on the cover's content.

**`tabViewBottomAccessory` draws its container as soon as it's attached,** leaving a permanent blank pill. Branch on whether the modifier is applied at all, not on the content inside it.

**A `Menu` whose label contains a `Spacer` anchors its popover to the centre of the screen** — the label becomes full-width. Move the `Spacer` outside the `Menu`.

**OCR crops landed off-image while looking correct.** `scaledToFit` letterboxed inside a larger `ZStack`; draw and store shared the same wrong transform, so the boxes rendered exactly where expected and cropped somewhere else entirely. Size the drawing surface to the image.

### Two corrected assumptions, recorded so they aren't re-researched

- **There is no "Apple Intelligence image model" API.** Foundation Models is text-only and hardware-gated to iPhone 15 Pro and up. Vision is the path for console OCR and it runs everywhere.
- **There is no separate Apple Fitness SDK.** Fitness is a HealthKit consumer; writing workouts to HealthKit is the whole integration.

**Calories are deliberately not written to HealthKit.** Without heart-rate data any figure would be invented, and Health passes it to other apps as fact.

### The OCR accuracy spike (§22.1), and why it shaped the UI

Whole-image OCR dropped a field on a clean photo and returned garbage on a blurred one. Naive crop-and-upscale scored 0/4. The recipe that worked — invert, greyscale, contrast 1.6, 2× upscale, and an **80px white margin**, which is not optional — scored 9/12.

One failure read `520` as `025`: reversed digits, a plausible wrong number that a user would never catch. Live verification then read `2415` as `2419`. That single class of failure is the entire argument for the scanner proposing values into an editable field and **never auto-submitting**.

### Verification habits that earned their keep

- **Read the SQLite store directly** rather than trusting the screen. The units work was confirmed by seeing `20.0` and `12.5` still stored as kilograms while the UI showed `44.1` and `27.6`.
- **Stretch an animation's duration** to screenshot a frame that would otherwise be impossible to catch.
- **Inspect the compiled bundle** (`assetutil`) to prove a resource actually reached the process that needs it.

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
