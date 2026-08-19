# Build 5 plan — device feedback on build 4

> **Status 2026-08-19: executed and verified.** Outcome table in [`SESSION-LOG.md`](SESSION-LOG.md) Session 5. This file is kept as the record of what was weighed and why.

Written 2026-08-19 from the first on-device test of build 1.0 (4). Each item records the report, what the research turned up, the options weighed, and the decision. Executed by scoped code agents; verified before commit.

Research inputs: three haiku web-research passes (iOS 26 swipe visuals; Core Haptics depth; sheet-vs-cover dismiss and keyboard toolbar), one opus code analysis (the Live Activity loop and empty-row deletion), and direct inspection of the current code.

---

## The three findings that reshape the plan

**1. The scroll jank and the "swipe-down closes from anywhere" have the same root: hand-rolled gestures fighting the scroll view.** `SwipeActionRow` installs a `UIPanGestureRecognizer` on the *shared* `UIScrollView` — one per row, never removed. A 6-exercise session puts ~24 recognizers on one scroll view, all evaluated per touch, and they accumulate as rows recycle. On top of that sits a SwiftUI `simultaneousGesture(DragGesture)` for dismiss. Research confirms `simultaneousGesture` on a scroll view is a known way to steal scrolling. **Both custom gestures go.** Dismiss becomes a system `.sheet` at `.large` detent, which arbitrates scroll-vs-dismiss correctly on its own; swipe becomes a *single* recognizer owned by the screen, dispatched to the row under the touch.

**2. The swipe actions look dated because they are drawn the iOS 7 way.** Full-height, edge-to-edge, flat coloured rectangles. iOS 26 renders swipe actions as inset rounded buttons (12–16pt radius) with 8–10pt gaps, a tinted translucent fill, icon over label, and the row keeps its own rounded background and slides over them. Redraw to that spec. (The reference is iOS 26 Mail — circles with labels beneath; see item B.)

**3. The haptics are tinny because every event is a bare transient at high sharpness.** Research is unambiguous: depth comes from a `hapticContinuous` body at **sharpness 0.2–0.35** for ≥200 ms with a softer transient (sharpness 0.3–0.5) layered ~100–150 ms in, and optionally a low tone. All-transient at sharpness 0.7–0.9 is exactly the "cheap click". Every pattern gets rebuilt to that recipe. **And a tuning surface ships with it**: haptics can only be judged by feel on a device, which the developer cannot do — so a hidden Haptics Lab screen with per-event sliders lets the person holding the phone tune the numbers and read them back.

---

## Items

### A. Workout screen presentation and scrolling
**Report:** any downward drag anywhere still dismisses; scrolling "messed up"; make it a full page if it can't be fixed.
**Options:** (a) keep `fullScreenCover`, delete every custom drag, dismiss only by chevron/pill tap; (b) `.sheet` + `.presentationDetents([.large])` + drag indicator, delete every custom drag, get system scroll-vs-dismiss for free; (c) keep trying to gate the custom gesture.
**Decision: (b), with (a) as the fallback if the sheet misbehaves with the keyboard on device.** Both delete the custom gesture code, which is also the scroll fix. (c) is rejected — three attempts at gating have already failed on device.
**Also:** remove the per-row pan recognizers; one recognizer at the screen level, dispatched by hit-test to the row.

### B. Swipe action visuals
**Report:** "straight from iPhone 6 days". Reference supplied: **iOS 26 Mail** swipe actions (Archive / Remind Me leading; More / Unread / Delete trailing).
**Spec, read off the reference:** each action is a **solid-filled circle ≈44pt** with a white SF Symbol centred; the **label sits below the circle, outside it**, in secondary grey caption text; ≈16pt between circles; the circles float on the page background (no strip); the row keeps its **rounded card background** and slides over them, revealing the circles progressively. Colours: red for Delete, orange for Drop, accent for Add Set. Rubber-band and detent haptic kept. This supersedes the earlier researched "icon-over-label pill" guess.

### C. Delete empty / un-ticked set rows
**Report:** can't swipe rows that aren't filled in, so unused rows can't be removed — and leftover ones trigger the superset prompt.
**Root cause (opus, two independent gates plus a latent bug):** `SetRowView` withholds Delete when `existingSet == nil`; *and* `ExerciseCardView` passes `existingSet: nil` for any row that isn't completed — so even a row that exists in the store loses Delete the moment it's un-ticked. Latent: `deleteExisting` never touched `plannedSetCount`, so with a nil plan the deleted row **reappears as a ghost immediately**.
**Decision:** every top-level row is swipeable and deletable. Delete captures `newCount = max(rowCount − 1, completedCount, 1)` first, removes the `SetLog` and its drops if one exists, renumbers, then sets `plannedSetCount = newCount`, shifts `addedRowSeed` keys, and calls `onPlanChanged()` (Live Activity refresh). If the deleted row owned the running rest, clear it. Rejected: a per-index "hidden" set — needs persistence, crash-recovery and an engine mirror; decrement + renumber keeps `plannedSetCount` the single source of truth. `···` → *Delete Last Set* stays as the failsafe.

### D. Superset prompt fires on ordinary "move to next exercise"
**Root cause (confirmed in code, two misfires):** `recordForDetection` gates on `hasIncompleteExpectedSets(previous)`, and that predicate (a) takes `expected` from **history ghosts only**, ignoring `plannedSetCount` — trim a plan to 2 sets while history says 3 and you're nagged forever; and (b) compares a *count* to `expected`, so with rows 0 and 2 ticked and row 1 empty, `2 < 3` holds for the rest of the session.
**Options weighed:** (i) opus's structural fix — `expected` = live plan, progress = highest completed row index, so ticking the last row ends detection; (ii) a timing gate — a superset has *no rest* between A and B, so only treat the alternation as a candidate if A's last set completed within A's rest duration (fallback 90 s); (iii) a settings toggle.
**Decision: all three.** (i) fixes the data model. (ii) closes the residual opus flagged — a trailing empty row you abandoned after a full rest is not evidence of anything. (iii) because the user called the feature stupid and PRD §7.8.1 frames it as a soft nudge; default on.

### E. Live Activity loop on an un-ticked middle set
**Root cause (opus, confirmed):** `WorkoutEngine.pointer(for:)` uses the **completed *count* as the row *index***. With rows 0 and 2 ticked, `completedCount == 2`, so the pointer resolves to `setIndex 2` — the row that is *already done*. `LogSetIntent` then finds that existing completed row and **overwrites it** (fresh `completedAt`, `loggedFrom = .liveActivity`, rest restarts) — the write succeeds on the wrong row, nothing fails, and `completedCount` never moves, so the exercise never ends. It also corrupts the `lastCompleted` anchor used for cold resolution.
**Fix:** the pointer selects the **first un-ticked slot** in `0..<planned`, where `planned = max(plannedSetCount ?? ghosts.count, topLevelRows.count, 1)` — the same helper `ExerciseCardView.rowCount` uses, extracted so the two can't diverge. Same slot logic in `thenLine`. **Plus a safety net in `LogSetIntent`:** an already-completed row is never rewritten from the Lock Screen, regardless of pointer state. Opus flagged one uncertainty — the superset `thenLine` round comparison (`completedCount < setNumber`) — to be re-checked after the change.

### F. Rest timer: one grabbable bar
**Report:** two bars — a progress bar and a slider under it — "makes no sense".
**Decision:** a single custom track. Capsule, fills with remaining time (drains), a small thumb at the fill edge; drag anywhere on it to set remaining time; the countdown label shows the scrubbed value while dragging. Skip stays as a text button. `Slider` removed.

### G. Keyboard dismissal (workout screen and onboarding)
**Report:** no way to close the number pad; onboarding keyboard likewise.
**Decision:** `.toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") } }` on the presented container, dismissing via `UIApplication` resign-first-responder so it works regardless of which row owns focus. Onboarding name field also gets `.submitLabel(.done)`. Known iOS 17 gotcha: toolbar sometimes appears on second focus inside `fullScreenCover`; moving the workout to a `.sheet` (A) sidesteps this.

### H. Onboarding
**Report:** name field should auto-capitalise after a space; no back button; that it scrolls isn't evident; the dominant-hand picker and the preview row read as separate things.
**Decision:** `.textInputAutocapitalization(.words)`; a *Back* button in the footer from page 2 onward; hand picker + preview + caption wrapped in one card so they read as a unit, with the tick animating across on change; a **new gestures page with two built-in illustrations** (a static row with Delete/Drop revealed on the left, a static row with Add Set revealed on the right) and one line each — drawn in SwiftUI from the real row components, no image assets.

### I. Haptics
**Report:** all feel tinny; the good ones have depth.
**Decision:** rebuild every event to the researched recipe (continuous low-sharpness body + softer transient; see rules above), lower all transient sharpness into 0.3–0.5, and ship **Haptics Lab** — a debug screen (Profile → long-press version, or a Settings toggle) listing every event with a Play button and sliders for intensity / sharpness / duration / layer offset, plus a "copy values" action. The person with the phone tunes; the numbers come back as text.

### J. Version
Bump `CURRENT_PROJECT_VERSION` to 5 before archive.

---

## Execution

Code agents (sonnet), one per non-overlapping file set:
1. **Presentation + gestures** — `RootTabView`, `ActiveWorkoutView` (dismiss/scroll), `SwipeActionRow` (single recognizer, new visuals). Highest risk; runs first and alone.
2. **Rows + engine** — `SetRowView`, `ExerciseCardView` (delete any row), `ActiveWorkoutView` superset gate, `WorkoutEngine` / intents per the opus fix. Depends on 1's row API being stable.
3. **Timer + keyboard** — `RestTimerBar`, keyboard toolbar.
4. **Onboarding** — `OnboardingView` only.
5. **Haptics + Lab** — `Haptics.swift`, new `HapticsLabView.swift`, entry point in Profile.

Verification before commit: build green; simulator pass on A/C/F/G/H; store check for C; the Live Activity loop reproduced then re-tested. Haptics and Lock Screen still need the phone.
