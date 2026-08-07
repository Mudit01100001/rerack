# M6 — Live Activity Interaction Design

**Status:** design, not built. Resolves the open questions in PRD §8.
**Scope:** the four ActivityKit presentations, superset and drop-set handling, the tick affordance and its limits, and the complete state machine.
**Does not change:** PRD.md. Where this document disagrees with §8, it says so explicitly in §10 and §11 below, and §8 should be amended before M6 starts.
**Code baseline:** the uncommitted M4/M5 working tree — `WorkoutEngine` with `nextSet(after:allExercises:ghostsProvider:)`, drop chains in `ExerciseCardView`, `DropSetMath`, `RestNotificationScheduler`, `RestTimerBar`. §3 and §9 are written against that, not against the last commit.

---

## 0. The one-sentence design

**There is one layout. It shows the next thing you will do, the exact numbers a tick will write, and a tick — and while a rest timer is running it additionally shows a countdown and a Skip button. Nothing else ever appears.**

Everything below is the consequence of that sentence.

---

## 1. Platform facts this design is built on

Five of these are in §8.2 already. Four are not, and their absence is why parts of §8.3–§8.4 are unbuildable as written.

| # | Fact | Consequence |
|---|---|---|
| P1 | Interactive controls are `Button` / `Toggle` only, via `LiveActivityIntent`. No text fields, steppers, sliders. | A tick logs the *displayed* values. See §6. |
| P2 | **Buttons exist only in the Lock Screen presentation and the expanded Dynamic Island.** Compact leading/trailing and minimal are non-interactive — a tap anywhere on them opens the app via `widgetURL`. | **You cannot log a set from the compact island.** The Lock Screen is the logging surface; the compact island is a glance surface. §8 never states this and §8.1's "glance, tap, rest, repeat" implies otherwise. This is consistent with Principle 2 ("The Lock Screen is the primary surface") but contradicts the compact-island framing. |
| P3 | Update pushes are throttled; a per-second countdown would blow the budget. `Text(timerInterval:)` and `ProgressView(timerInterval:)` decrement on-device with zero updates. | The countdown is a `Text(timerInterval:countsDown: true)` over an absolute end `Date`. |
| P4 | **Corollary to P3 that §8.2 omits: nothing *except* those two views can change when the timer reaches zero.** A widget body is rendered when an update arrives, not on a schedule. There is no local mechanism to fire an `Activity.update` at T=0 from a suspended app, and we have no push server (§12, zero recurring cost). | **A "rest is over / GO" state cannot be guaranteed.** See §5.4. The design must be correct and usable whether or not that transition ever lands. |
| P5 | `ProgressView(timerInterval:)` gives a determinate **linear** bar that animates on-device (`RestTimerBar` already uses it in-app, and it stays there). There is no determinate **circular** equivalent on iOS, and a custom ring cannot be animated without updates. | §8.3's minimal presentation ("a filled ring showing rest progress") is not buildable. See §4.4. The bar is buildable on the larger presentations and is cut for design reasons, not platform ones — see §10. |
| P6 | Activities go stale ~8h, are force-ended ~12h, and do not survive a device reboot. | §7 rows 32, 33, 35. |
| P7 | `LiveActivityIntent` relaunches the app process in the background to run `perform()`. | Ticking works with the app force-quit. It also means an intent is the *only* reliable moment the activity content can be repaired. |
| P8 | The widget extension is a separate process reading the App Group store. It cannot see SwiftUI `@State`. | Two current blockers — see §9. |
| P9 | `ContentState` is `Codable` and capped at 4 KB. | Ample. Lets us pre-compose display strings in the app so the widget stays a dumb renderer (§8). |

---

## 2. The content priority ladder

One ordered list of everything the Live Activity may ever show. Each presentation states how far down the list it goes. **Within a presentation, Dynamic Type or localisation overflow drops from the bottom of the ladder upward — never truncates mid-item, never wraps.**

| Rank | Element | Present when |
|---|---|---|
| **1** | **Payload** — the weight × reps a tick will write | always (may render as *unknown*, §6.2) |
| **2** | **Tick** ✓ | payload is known, activity is not stale |
| **3** | **Position** — `Set 3 of 4` / `Round 3 of 4` / `Drop 1 of 2` / `Warm-up` | always |
| **4** | **Rest countdown** | resting only |
| **5** | **Exercise name** (with superset `A1` badge) | always |
| **6** | **"Then" line** | only when the pointer's next step changes exercise (§5.2) |
| **7** | **Skip** | resting only |
| **8** | **Adjust** `⋯` | Lock Screen only |
| **9** | **Routine name** | Lock Screen only |

| Presentation | Reaches | Cuts |
|---|---|---|
| Minimal | 4 only | everything else — one glyph of space |
| Compact | 3 + (4 while resting, else 1) | no room, and no buttons (P2) |
| Dynamic Island expanded | 1–7 | 8 (whole surface is already the deep link), 9 (you long-pressed *this* activity; you know what it is) |
| Lock Screen | 1–9 | nothing |

Rank 1 sits above rank 2 deliberately: if the numbers can't be shown, the button must not be shown either. A button whose payload is invisible is a button that writes something you didn't agree to.

---

## 3. The pointer

Everything on the island is a rendering of one value: **the next set**. §8.4 says there is exactly one implementation shared with the in-app screen — and as of M5 that implementation exists: `WorkoutEngine.nextSet(after:allExercises:ghostsProvider:)`, built to feed the rest-complete notification's "Next:" line.

**The island must use that function, not a second copy.** But it needs five changes first, all of them small and all of them improvements to the in-app behaviour too. What follows is the target shape; §3.1 lists the deltas.

```
nextSet(workout) →
  1. DROP CHAINS FIRST.
     If the most recently completed set has an unfinished drop chain
     (planned drop children with no completed SetLog), return the first
     of those. A drop chain is never interrupted by anything.

  2. Identify the ACTIVE UNIT: the superset group, or the standalone
     exercise, that owns the most recently completed set.

  3. If the active unit is a SUPERSET GROUP:
       round      = completedCount(currentMember)          // after the tick
       candidates = members after currentMember in orderIndex order
       next       = first candidate with completedCount < round
                    AND plannedSetCount > completedCount
       if none    = wrap to the first member (orderIndex order) with
                    completedCount == round AND sets remaining  → round + 1
       if still none → the group is exhausted; fall through to step 5.

  4. If the active unit is STANDALONE:
       next = first incomplete planned set index of that exercise
       if none → fall through to step 5.

  5. Advance to the next unit by orderIndex (a group is entered at its
     first member with sets remaining). Repeat from step 3.

  6. If no unit has sets remaining → pointer = nil ("all planned logged").
```

Two definitions this depends on:

- **`plannedSetCount(workoutExercise)`** = `max(ghostSets.count + manually added rows, completedSets.count, 1)` — the same expression `ExerciseCardView.rowCount` already uses. **It must be persisted.** See §9.1.
- **Round total for a group** = `max(plannedSetCount)` across members. A member that runs out is skipped in later rounds (§7.8), which step 3 already does.

`WorkoutEngine.shouldStartRest(after:hasPendingDrop:allExercises:)` as built is consistent with step 3 and needs no change. It answers "does rest start"; the pointer answers "what's next". Both are needed and they are different questions. Its `completedCount` already excludes drop children (`parentSetID == nil`), which is what makes "round" mean the right thing above.

### 3.1 Deltas against the shipped `WorkoutEngine.nextSet`

| # | Shipped behaviour | Needed for M6 | Why |
|---|---|---|---|
| D1 | Signature is `nextSet(after: workoutExercise, …)` — relative to a just-completed exercise | Add an absolute entry point `nextSet(in: workout, …)` that resolves from the most recently completed set, with the existing function as its inner loop | On launch, crash recovery, or an activity restart (§7 rows 1, 31, 35) there is no "after" anchor. The island must be able to ask "what's next" cold. |
| D2 | `pointer(for:)` returns nil when `completed >= ghosts.count`, so an exercise with **no ghosts and no routine target is skipped entirely** | Land on it, and return a pointer with an unresolved payload | Otherwise §5.3's `No target yet` / `Open` state is unreachable, and a brand-new exercise silently vanishes from the island — the exact case where the user most needs the app opened. The in-app card already renders it (`rowCount` floors at 1); the pointer disagrees with the card today. |
| D3 | Expected length is `ghosts.count` | `plannedSetCount` (§9.1) | Otherwise `+ Add Set` is invisible to the pointer, and the island advances off an exercise you are still working on. |
| D4 | No drop-chain handling — drops are handled only in `shouldStartRest` via the caller's `hasPendingDrop` flag | Step 1 of §3: an open drop chain outranks everything | The pointer is what the island renders, so without this the island shows the *next set* while you are standing there mid-drop-chain. Requires §9.3. |
| D5 | `NextSetPointer` carries name, set number, weight, reps | Also needs: `workoutExerciseID`, `setIndex`, `supersetLabel`, planned total, drop position, and a payload-known flag | These are the intent's target parameters and the position/badge slots. The notification only needed a sentence; the island needs an address. |

Every one of these makes the notification's "Next:" line more correct too, which is the argument for fixing them in the shared function rather than forking.

---

## 4. The four presentations

Sketches use the PRD §8.3 style. Widths are indicative, not pixel-exact.

### 4.1 Lock Screen / Notification Center — the primary surface

Four rows, fixed. Row 4 is conditional. This is the only presentation with `⋯` and the routine name.

**Logging, standalone exercise — the most common state in the whole product**

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                              │
│                                                          │
│  Seated Cable Row                            Set 3 of 4  │
│                                                          │
│  12 kg × 6                          ⋯       ╭─────────╮  │
│                                             │    ✓    │  │
│                                             ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Resting** — identical, plus a countdown in the header slot and a Skip button. The exercise, payload and tick shown are *the next set*, not the one you just finished.

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                        1:42  │
│                                                          │
│  Seated Cable Row                            Set 4 of 4  │
│                                                          │
│  12 kg × 6                    ⋯   ╭──────╮  ╭─────────╮  │
│                                   │ Skip │  │    ✓    │  │
│                                   ╰──────╯  ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Logging, inside superset A, on the first member**

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                              │
│                                                          │
│  A1  Incline DB Press                      Round 3 of 4  │
│                                                          │
│  15 kg × 10                         ⋯       ╭─────────╮  │
│                                             │    ✓    │  │
│  Then  A2 Cable Fly · 12 kg × 12            ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Logging, inside superset A, on the last member of the round** — this is the state §7.8.1 says the island exists for.

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                              │
│                                                          │
│  A2  Cable Fly                             Round 3 of 4  │
│                                                          │
│  12 kg × 12                         ⋯       ╭─────────╮  │
│                                             │    ✓    │  │
│  Then  rest, back to A1 Incline DB Press    ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Mid drop chain** — no countdown, because there is no rest. The absence of the timer *is* the "go now" signal.

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                              │
│                                                          │
│  Seated Cable Row                           Drop 1 of 2  │
│                                                          │
│  10 kg × 8                          ⋯       ╭─────────╮  │
│                                             │    ✓    │  │
│                                             ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Payload unknown** — brand-new exercise, no history, no routine target. No tick.

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                              │
│                                                          │
│  Landmine Press                                   Set 1  │
│                                                          │
│  No target yet                              ╭─────────╮  │
│                                             │  Open   │  │
│                                             ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**All planned sets logged** — pointer is nil. `Finish` is a deep link, not an intent (§7 row 13).

```
┌──────────────────────────────────────────────────────────┐
│  PUSH DAY A                                        0:47  │
│                                                          │
│  All planned sets logged                                 │
│                                                          │
│                                             ╭─────────╮  │
│                                             │ Finish  │  │
│                                             ╰─────────╯  │
└──────────────────────────────────────────────────────────┘
```

**Stale (~8h, P6)** — same layout, tick replaced by `Open`. We will not let you log a set against eight-hour-old state without looking at it. No nag copy.

**Metrics.** Container height ~104pt with the Then line, ~88pt without. Routine name `.caption2` uppercase `.secondary`, tracking +0.5. Exercise name `.headline`. Position `.caption` `.secondary`. Payload `.title3` `.monospacedDigit()` `.primary`. Then line `.caption` `.secondary`. Tick 64×44pt, Skip 60×44pt, `⋯` 44×44pt, all ≥44pt per §17. Superset badge: `.caption2.bold()` white on an accent capsule, matching `ExerciseCardView`'s existing badge exactly.

### 4.2 Dynamic Island — expanded (long press)

Same content minus the routine name and `⋯`. Region mapping:

| Region | Content |
|---|---|
| `.leading` | Position token (`3/4`, `A2`, `D1`, `W`) — accent |
| `.trailing` | Countdown while resting; empty while logging |
| `.center` | Exercise name, one line, truncating tail |
| `.bottom` | Payload + tick; Skip while resting; Then line when it applies |

```
╭──────────────────────────────────────────────╮
│  A1        Incline DB Press                  │
│                                              │
│   15 kg × 10                     ╭────────╮  │
│                                  │   ✓    │  │
│   Then  A2 Cable Fly · 12 kg × 12╰────────╯  │
╰──────────────────────────────────────────────╯

╭──────────────────────────────────────────────╮
│  3/4       Seated Cable Row           1:42   │
│                                              │
│   12 kg × 6         ╭──────╮     ╭────────╮  │
│                     │ Skip │     │   ✓    │  │
│                     ╰──────╯     ╰────────╯  │
╰──────────────────────────────────────────────╯
```

The whole non-button area is a `Link` to `rerack://workout/active`.

### 4.3 Dynamic Island — compact

Two slots, no buttons (P2). Exactly one fact per slot.

```
      ╭───────────────────────────────╮
      │ 3/4                    12×6   │   logging, standalone
      ╰───────────────────────────────╯

      ╭───────────────────────────────╮
      │ A2                     1:42   │   resting, inside superset A
      ╰───────────────────────────────╯

      ╭───────────────────────────────╮
      │ D1                     10×8   │   mid drop chain
      ╰───────────────────────────────╯
```

**Leading token — one token, never composed. The most specific fact wins:**

| Condition | Token | Why this beats the alternatives |
|---|---|---|
| Pointer is a drop set | `D1` | "no rest, go lighter, now" is the only thing that matters |
| Pointer is a warm-up | `W` | matches the in-app Set # column (§7.2) |
| Pointer is inside a superset | `A2` | which member you're on changes every set and cannot be guessed; the round can be |
| Otherwise, total known | `3/4` | |
| Otherwise, total unknown | `#3` | bare `3` is ambiguous |

**Trailing token:**

- Resting → `Text(timerInterval:)` → `1:42`
- Logging → payload, formatted `{weight}×{reps}`; weight to at most one decimal, trailing `.0` dropped. If the composed string exceeds 6 glyphs, drop `×{reps}` and show weight alone (`12.5`). Bodyweight-load exercises show `×10`. Unknown shows `—`.

The trailing slot changes meaning between phases, which is normally a sin. It is defensible here because the two are mutually exclusive, typographically distinct (`1:42` has a colon and visibly ticks; `12×6` has a `×` and is static), and the slot's *job* is stable: it is always "the number that matters right now". It replaces §8.3's proposed `GO`, which carries no information and, per P4, cannot be shown at the right moment anyway.

### 4.4 Dynamic Island — minimal

One ~30pt slot. §8.3's "filled ring showing rest progress" is not buildable (P5).

- **Resting:** the countdown, `Text(timerInterval:)`, `.caption2` `.monospacedDigit()` `.minimumScaleFactor(0.7)`. `1:42` fits comfortably; a 10:00 rest scales down for its first second.
- **Not resting:** `dumbbell.fill`, accent-tinted.

Nothing else. Minimal exists because a *different* app's activity is more important right now; it should not compete.

---

## 5. The four resolved questions

### 5.1 Supersets — solved by one drop rule, not by a new widget

I considered and rejected a "round strip" (`↻3 · A1 ▸ A2 ▸ ⏱`). It is dense, needs learning, and is the exact species of ornament that makes Knurl read as cluttered.

The solution is a rule about *when a line appears*:

> **The "Then" line appears only when the pointer's next step changes exercise.**

Consequences, all of them good:

- Straight sets: the next step is the next set of the same exercise, which `Set 3 of 4` already says. The line is **absent**. The Lock Screen is three rows and a button — the sparsest it can be, in the most common state.
- Supersets: the exercise changes on **every single set**, so the line is **always present**. Its presence is itself the superset signal, before you read a word of it.
- The line is therefore never noise. It only appears when it is the only place the information exists.

Wording, by pointer position:

| Pointer position | Then line |
|---|---|
| Superset member, not last of round | `Then  A2 Cable Fly · 12 kg × 12` |
| Superset member, last of round, rounds remain | `Then  rest, back to A1 Incline DB Press` |
| Superset member, last of round, group exhausted | `Then  Lat Pulldown` |
| Standalone, last planned set of the exercise | `Then  Lat Pulldown` |
| Anything else | *(absent)* |

The payload (`· 12 kg × 12`) is included **only** for the immediate next superset member — the one you will walk to in about two seconds. Anything on the far side of a rest omits it, because by the time you get there the island will be showing it as the main payload.

And the position slot reads `Round 3 of 4` instead of `Set 3 of 4` inside a group, because in round-robin execution they are the same number and "round" is the true one.

Walk the loop and check it reads correctly:

| Moment | Main line | Then line |
|---|---|---|
| Logging A1, round 3 | `A1 Incline DB Press · 15 kg × 10` | `Then A2 Cable Fly · 12 kg × 12` |
| Tick → logging A2, round 3 (no rest) | `A2 Cable Fly · 12 kg × 12` | `Then rest, back to A1 Incline DB Press` |
| Tick → resting, pointer A1 round 4 | `A1 Incline DB Press · 15 kg × 10` · `1:42` | `Then A2 Cable Fly · 12 kg × 12` |

Every state answers "next is A2, then back to A1" without ever implying linear progression. §7.8.1's requested sentence appears verbatim on the surface it was requested for.

**Intra-superset rest** (§7.8, default 0:00): when configured non-zero, ticking a non-final member enters RESTING normally. No special presentation — the countdown plus a Then line that names the partner already reads correctly. The button row stays fixed (Skip + tick) regardless of rest length; consistent muscle memory beats a conditional control set for chalky hands.

### 5.2 Drop sets — solved by an absence

A drop chain means "no rest, immediately, lighter". Two changes, zero new elements:

1. **Position slot reads `Drop 1 of 2`** (compact: `D1`). That is one existing slot showing a different string.
2. **No countdown appears.** The pointer stays in LOGGING (§7.9's rest suppression). The island that has a timer on it means "wait"; the island that doesn't means "go". You already learn that rule from every other state, so the drop chain teaches you nothing new.

Explicitly rejected: showing the decrement as `15 ▸ 10 kg × 8`. It reads well but it puts two numbers in the payload slot when exactly one of them is what the tick writes, and that breaks the WYSIWYG contract in §6.1 — the one contract that makes the button trustworthy.

Also rejected: a "no rest" caption. It states what the missing timer already states.

The `−20%` pre-fill happens in the app when the drop row is created (`DropSetMath.prefillWeightKg`); the island only ever renders the resulting number.

**This design is unaffected by M4's known gap** — that ghost sets do not yet reproduce a drop chain next session (§7.9's closing bullet, deferred to M8). The island's drop payload comes from the live pre-fill off the parent you just ticked, never from history, and the chain total (`of 2`) counts the drops you have added in *this* session. Drop chains therefore work on the island from day one of M6. When M8 lands ghost drop chains, nothing here changes except that the chain is pre-populated rather than grown by hand — the same states, reached earlier.

### 5.3 The tick, and what it honestly cannot do

**The contract (§6.1):** the payload shown is the payload written. Byte for byte.

**When the payload is unknown**, the tick is *absent*, not disabled. A greyed button invites a tap that does nothing; an absent one tells the truth. In its place, `Open` deep-links to that set row with the weight field focused and the keypad up. Three states, decided by data that already exists in the schema:

| Payload state | Condition | Renders | Tick |
|---|---|---|---|
| `known(w, r)` | ghost or routine target resolved both values | `15 kg × 10` | ✓ enabled |
| `repsOnly(r)` | reps known, weight unknown, **and** `Exercise.loadType == .bodyweight` | `10 reps` | ✓ enabled — writes weight 0, which §7.2 explicitly allows and §13.1 makes correct |
| `unknown` | anything else, including reps-known-but-`loadType == .external` | `No target yet` | replaced by `Open` |

When the total is unknown (a brand-new exercise has no ghost list, so `plannedSetCount` is 1 and grows), the position slot drops "of N": `Set 1`, then `Set 2`. Compact shows `#2`.

**The `⋯` / Adjust escape hatch.** A `Link` to `rerack://workout/active?focus={workoutExerciseID}&set={index}&field=weight`, opening the app scrolled to that row with the keypad up. **Lock Screen only.** It is cut from the expanded island because the entire non-button area there is already the same deep link minus the focused keypad, and the expanded island is the space-constrained surface of the two. `⋯` has an accessibility label of "Adjust this set"; the glyph stays because a word in that slot would compete with `Skip` and `✓` for reading order.

**The island logs the plan. Deviating from the plan requires the app.** There is no add-set, no add-exercise, no weight adjustment, no un-tick on the island — see §10. That is the honest boundary of a surface with no text input, and stating it plainly is better than approximating typing with buttons.

**Settings — `Island tick logs:` (§8.5, §10.2, Q11).** See §11 item 7: this setting as specified creates a state where the island and the in-app ghost row show different numbers for the same set, which violates Principle 5. Recommendation: either cut it, or make it a global `Ghost values prefer:` setting that changes §7.3's source priority everywhere. Default stays `Last session's values` either way.

### 5.4 The ready state, which does not exist

§7.5 says "Live Activity switches to the 'ready' state"; §8.3 says the compact trailing shows `GO when ready`. Per P4, **neither can be guaranteed**: at T=0 the app is typically suspended, no local mechanism fires an `Activity.update`, and we have no push server.

Rather than build a state that works intermittently, the design removes the need for one:

> **RESTING is LOGGING plus two things: a countdown and a Skip button.** The exercise, the payload and a live tick are present and correct in both.

So when the countdown reaches `0:00` and no update arrives, the surface is *already* the correct logging surface. The stale element is a `0:00` that should have vanished — cosmetic, not functional. Any subsequent intent tap, or the app coming to foreground, repairs it.

This also fixes a real defect: §8.3's expanded resting layout has **no tick at all**, so finishing rest early costs two taps (Skip, then re-expand and tick) and the surface is unusable if the T=0 update never lands. With the unified layout, finishing early is one tap on ✓, which cancels rest and logs — matching §7.5's "ticking a new set restarts the timer; it does not stack."

---

## 6. Write semantics

### 6.1 What the tick writes

`LogSetIntent` carries four parameters: workout-exercise id, set index, weight, reps — the displayed values, not a reference to be re-resolved.

On perform:

1. Re-resolve the pointer from the store.
2. If the pointer still equals (workout-exercise id, set index) → write `weight`/`reps` as carried, `isCompleted = true`, `completedAt = now`, `loggedFrom = .liveActivity`, recompute cached stats, start rest per `WorkoutEngine.shouldStartRest`, push the new content state. `.success` haptic.
3. If the pointer has moved (the set was already logged or edited in-app) → **write nothing.** Push the corrected content state. `.warning` haptic. The tap visibly changed the island to the truth, which is the honest outcome; it did not silently write a number into a row you didn't mean.

This resolves a contradiction §15 currently contains — see §11 item 6. The **values** come from the intent (WYSIWYG, §8.5). The **target** is re-resolved from the store (freshness, §15). Both requirements are satisfiable at once; the current wording is not.

### 6.2 The tick is a Button, not a Toggle

A `Toggle` would give un-tick for free, which is tempting. It doesn't work: the moment a set is logged the pointer advances, so the toggle's "on" state has nowhere to live — the row it refers to is no longer the row the island is showing. Un-tick is in-app only (§7 row 19). The cost of an accidental tap is one correction in the app; the cost of a second button is permanent.

### 6.3 Deep links

| Target | URL |
|---|---|
| Whole activity, any presentation | `rerack://workout/active` |
| `⋯` / `Open` | `rerack://workout/active?focus={workoutExerciseID}&set={index}&field=weight` |
| `Finish` | `rerack://workout/active?finish=1` |

`Finish` is a deep link and never an intent: finishing is effectively irreversible, and §9.4's finish flow (photo, tags, PR review) needs the app anyway.

---

## 7. State transition table

Phases: **LOGGING**, **RESTING**. That is the entire enum. "Ready", "Finished" and "All done" are not phases — see §11 items 2 and 4. All-planned-logged is LOGGING with a nil pointer.

| # | From | Trigger | Origin | To | Content change |
|---|---|---|---|---|---|
| 1 | — | Workout started from a routine | app | LOGGING | Activity created, pointer = first set of first unit |
| 2 | — | Workout started empty | app | LOGGING | pointer nil → `No exercises yet` + `Open`; no tick |
| 3 | LOGGING | First exercise added | app | LOGGING | pointer resolves, tick appears |
| 4 | LOGGING | ✓ standalone, sets remain | island or app | **RESTING** | pointer = same exercise, next set index |
| 5 | LOGGING | ✓ standalone, last planned set, more units remain | island or app | **RESTING** | pointer = next unit's first set; Then line was shown before the tick |
| 6 | LOGGING | ✓ superset member, not last of round, intra-rest = 0 | island or app | **LOGGING** | no countdown; pointer = next member, same round |
| 7 | LOGGING | ✓ superset member, not last of round, intra-rest > 0 | island or app | **RESTING** | short countdown; pointer = next member, same round |
| 8 | LOGGING | ✓ last member of round, rounds remain | island or app | **RESTING** | pointer = first member with sets remaining, round + 1 |
| 9 | LOGGING | ✓ last member of last round, group exhausted | island or app | **RESTING** | pointer = next unit by orderIndex |
| 10 | LOGGING | ✓ parent set that has planned drop children | island or app | **LOGGING** | no countdown; pointer = first drop; position → `Drop 1 of N` |
| 11 | LOGGING | ✓ drop set, more drops in the chain | island or app | **LOGGING** | pointer = next drop; position → `Drop 2 of N` |
| 12 | LOGGING | ✓ last drop in the chain | island or app | **RESTING** | pointer resolves as if the parent's slot had just completed (rows 4–9) |
| 13 | LOGGING | ✓ and nothing planned remains anywhere | island or app | **RESTING** | countdown runs (you did do a set); pointer nil → `All planned sets logged` + `Finish`; no tick |
| 14 | either | ✓ but the pointer has moved since the state was pushed | island | unchanged phase | No write. State refreshed to truth. `.warning` haptic (§6.1) |
| 15 | either | Tap on a payload-unknown state | island | — | Not possible: no tick is rendered (§5.3) |
| 15a | LOGGING | Pointer lands on an exercise with no history and no routine target | app | LOGGING | Payload `unknown` → `No target yet` + `Open`; position drops "of N" (`Set 1`); compact shows `#1`. Requires delta D2 (§3.1) — the shipped pointer skips such an exercise entirely |
| 16 | RESTING | `Skip` | island or app | **LOGGING** | countdown and Skip removed; `restStartedAt` cleared |
| 17 | RESTING | Rest reaches 0:00, app suspended | — | **RESTING** (unrepaired) | **No transition (P4).** Countdown reads `0:00`; tick and payload already correct and live |
| 18 | RESTING | Rest reaches 0:00, app foregrounded or an intent runs | app | **LOGGING** | countdown and Skip removed; local notification per §7.5 |
| 19 | either | **Un-tick** a set | app only | LOGGING | Rest cancelled if that set started it. Pointer moves back to the un-ticked slot. Payload = the un-ticked set's own values, so re-ticking is idempotent |
| 20 | either | Set deleted (swipe left) | app only | phase unchanged | Indices renumber; pointer recomputed; payload refreshed |
| 21 | either | Set values edited | app only | phase unchanged | Payload refreshed only. If the edited set is not the pointer, no visible change |
| 22 | either | `+ Add Set` | app only | phase unchanged | `plannedSetCount` +1; position total updates (`Set 3 of 5`); if pointer was nil it resolves |
| 23 | RESTING | `+ Drop` added to the set that started the rest | app only | **LOGGING** | Rest cancelled — a drop chain admits no rest (§7.9). Pointer = the new drop |
| 24 | either | Superset created (explicit `···` or auto-detected §7.8.1) | app only | phase unchanged | Position → `Round n of m`; `A1`/`A2` badge appears; Then line appears; pointer recomputed to round-robin |
| 25 | either | Superset dissolved, or a member removed leaving one | app only | phase unchanged | Inverse of row 24; Then line disappears if the next step no longer changes exercise |
| 26 | either | Exercise removed | app only | phase unchanged | Pointer recomputed. If the removed exercise held the pointer, advance; if it started the rest, cancel it |
| 27 | either | Exercises reordered | app only | phase unchanged | Pointer recomputed by orderIndex |
| 28 | either | Workout finished | app only | — | `Activity.end(dismissalPolicy: .immediate)`. No FINISHED presentation (§11 item 4) |
| 29 | either | Workout discarded | app only | — | `.end(.immediate)` |
| 30 | either | Abandoned workout resolved at launch (>12h, §7.7) | app only | — | Finish-backdated or discard; either way `.end(.immediate)` |
| 31 | either | User swipes the activity away | system | — | Workout continues. In-app banner gains `Show on Lock Screen` (§8.6) |
| 32 | either | `isStale` (~8h) | system | phase unchanged | Tick replaced by `Open`. Layout otherwise identical. No nag copy |
| 33 | either | System force-end (~12h) | system | — | Activity gone; workout may still be live; in-app banner offers restart |
| 34 | either | ✓ tapped while the app is force-quit | island | per rows 4–13 | Intent relaunches the process in the background (P7), writes, pushes |
| 35 | either | Device reboot | system | — | Activities do not survive reboot. Crash recovery (§7.7) restores the workout and re-creates the activity |
| 36 | RESTING | ✓ tapped before the countdown ends | island | per rows 4–13 | Rest cancelled and restarted from the new tick; does not stack (§7.5) |
| 37 | — | Live Activity permission denied | system | — | No activity ever created. In-app banner and rest timer unaffected. No repeat prompt (§15) |
| 38 | LOGGING | Pointer is a warm-up set | — | LOGGING | Position reads `Warm-up` (compact `W`). Ticking starts rest as normal — consistent with `shouldStartRest`, which does not special-case warm-ups |

---

## 8. Activity state shape

Static `ActivityAttributes`: workout id, and the workout title (frozen at start — `routineNameSnapshot` or the empty-workout title; nothing in the app edits it mid-session).

Dynamic `ContentState`:

| Field | Type | Purpose |
|---|---|---|
| `phase` | `logging` / `resting` | the whole enum |
| `restEndsAt` | `Date?` | absolute instant; drives `Text(timerInterval:)`. Non-nil iff resting |
| `workoutExerciseID` | `UUID?` | intent target and deep-link focus. Nil ⇒ all planned logged |
| `setIndex` | `Int` | intent target |
| `exerciseName` | `String?` | rank 5 |
| `supersetLabel` | `String?` | `"A1"` — nil when standalone |
| `positionLabel` | `String` | pre-composed: `Set 3 of 4` / `Round 3 of 4` / `Drop 1 of 2` / `Warm-up` / `Set 1` |
| `compactToken` | `String` | pre-composed: `3/4` / `A2` / `D1` / `W` / `#3` |
| `payload` | `known(Double, Int)` / `repsOnly(Int)` / `unknown` | ranks 1 and 2 |
| `thenLine` | `String?` | pre-composed; nil ⇒ line absent (§5.1) |

Everything textual is **composed in the app, not the widget**. One implementation of the wording, one place to fix it, and the widget never touches SwiftData or `GhostSetResolver`. Well under the 4 KB cap.

---

## 9. Prerequisites found in the current code — three blockers

### 9.1 `plannedSetCount` is view state and must be persisted

`ExerciseCardView` computes `rowCount = max(ghosts.count + extraRows, completedSets.count, 1)`, where `extraRows` is `@State private var extraRows = 0`. `SetLog` rows are only inserted on completion, so an added-but-unticked row has no database presence at all.

Two consequences: the widget process cannot see it (P8), so the island cannot render `Set 3 of 5` after you tap `+ Add Set`; and it resets when the view is torn down, which is an existing in-app defect independent of M6.

**Fix before M6:** persist a `plannedSetCount: Int?` on `WorkoutExercise`, defaulting to the resolved ghost count and incremented by `+ Add Set`. The pointer (§3) depends on it.

### 9.2 Rest state is view state and must be persisted

`ActiveWorkoutView` holds `restingExerciseID`, `restStartedAt` and `restAdjustSeconds` as `@State`. `SetLog.restStartedAt` is persisted, but there is no persisted rest *duration*, no persisted "skipped" marker, and no way for a `SkipRestIntent` running in the background process to clear a `@State` variable in a view that isn't instantiated.

**Fix before M6:** derive rest entirely from persisted values — an absolute `restEndsAt: Date?` on `Workout` (or on the `SetLog` that started it), cleared on skip and on un-tick. The island's countdown, the local notification (§7.5) and the in-app bar then all read the same instant, which also satisfies §17's ±1s accuracy requirement for free.

### 9.3 Pending drop rows are view state — the drop design in §5.2 depends on fixing this

`ExerciseCardView` holds `@State private var pendingDrops: [PendingDrop] = []`, and `WorkoutEngine`'s own doc comment names the consequence: *pending drops are pure view state and this engine only sees persisted data*, which is why `shouldStartRest` takes `hasPendingDrop` as a caller-supplied flag rather than computing it.

That is a defensible in-app shape. It does not survive the process boundary. The widget cannot see `pendingDrops`, so it cannot know a drop chain is open, so it cannot render `Drop 1 of 2` or suppress the countdown — **the whole of §5.2 is unreachable** — and a `LogSetIntent` running in the background has no way to pass a truthful `hasPendingDrop`, so ticking the parent set from the Lock Screen would start a rest timer that §7.9 forbids.

**Fix before M6:** give a planned drop row database presence before it is ticked. Either a lightweight `plannedDropCount` on the parent `SetLog`, or insert the drop `SetLog` at creation with `isCompleted = false` (which also makes the drop chain survive a force-quit, matching Principle 4 "never lose a set" — an unticked drop row is currently lost on relaunch). The second is the better shape and lets `shouldStartRest` compute `hasPendingDrop` itself, retiring the parameter.

### 9.4 Smaller notes

- `SetLog.loggedFrom` already exists (`LoggedFrom.liveActivity`); the intent must set it. §17 calls this the most interesting number in the product once M6 ships.
- `SupersetGrouping.label(for:among:)` already produces `A1`/`A2` from `orderIndex`. The island should call it, not re-derive.
- `DropSetMath.prefillWeightKg` runs in the app when the row is created. The island only ever renders the result — no maths in the widget.
- `RestNotificationScheduler` (M5) and the island countdown must read the same absolute end instant, or the notification and the island will disagree by whatever `restAdjustSeconds` held. §9.2 fixes both at once.

---

## 10. What I deliberately left out, and why

| Cut | Why |
|---|---|
| **Workout elapsed time** (`24:11` in §8.3's Lock Screen sketch) | You cannot act on it mid-set, and it competes for the one header slot that must belong to the rest countdown. A slot that means "elapsed" sometimes and "remaining" other times is the specific thing that makes a glance surface unreadable. It stays in-app (§7.6) and in the finish summary. |
| **Live volume and set count** | Same reasoning, weaker case. Pure end-of-session stats. |
| **PR badge 🏆** | The clearest example of a thing that doesn't earn its space. It can only appear *after* a tick, needs a slot of its own, and changes nothing you do next. It stays inline in-app (§7.2). |
| **Rest progress bar / ring** | The linear bar is perfectly buildable — `RestTimerBar` already uses `ProgressView(timerInterval:)` in-app and keeps it, where there is room. On the island it duplicates the countdown, which is the precise version of the same fact, so it is cut from the expanded island and the Lock Screen by choice. The *ring* in §8.3's minimal sketch is a separate matter: not buildable at all (P5). |
| **`−15s` and `+15s`** | `−15s` is dominated by `Skip` for the only case it serves. `+15s` buys "don't buzz me yet", which is marginal and useless once the timer has already hit zero. Cutting both takes the resting control set from three buttons to one, doubles the remaining targets' size, and is the single biggest step under the Knurl bar. All three survive in the in-app timer sheet (§7.5) where precision is appropriate. Reversible in one line if two weeks of use says otherwise. |
| **`GO` / a ready state** | Cannot be delivered at the right moment (P4). Replaced by making RESTING structurally identical to LOGGING, so no transition is needed. |
| **A FINISHED presentation** | The app cannot know you are finished — `+ Add Set` always exists. Declaring completion on your behalf is coach behaviour (Principle 8). And you can only finish in-app, so a summary card would appear behind the summary screen. |
| **Un-tick / undo on the island** | The pointer advances on tick, so a `Toggle`'s on-state has no row to refer to (§6.2). One rare correction in-app costs less than a permanent second button. |
| **`+ Add Set`, add exercise, replace exercise** | The island logs the plan; changing the plan is what the app is for. Approximating a text field with buttons is how this surface becomes Knurl. |
| **RPE** | Off by default in-app (§18 Q8); a self-report has no business on a one-tap surface. |
| **`⟨ same as last time ⟩`** (§8.3) | Fights §8.5's own WYSIWYG rule by framing the payload as a hint, is sometimes false (routine-target source), and Principle 5's grey-means-suggestion does not apply here — see §11 item 8. |
| **A superset "round strip"** (`↻3 · A1 ▸ A2 ▸ ⏱`) | Considered seriously and rejected. Denser than the Then line, needs learning, and encodes "rest comes after A2" — a behaviour you experience rather than need announced. |
| **Next-exercise look-ahead during straight sets** | §8.3's Lock Screen shows `Up next: Lat Pulldown` while on set 3 of 4 of Seated Cable Row. That is not what's next. See §11 item 1. |
| **Routine name on the expanded island** | You long-pressed this activity. You know which one it is. |
| **Any motivational, evaluative or advisory copy** | Principle 8. There is not one adjective on any of these four surfaces. |

---

## 11. Where I believe §8 is currently wrong

1. **§8.3, Lock Screen — `Up next: Lat Pulldown` while showing `Set 3 of 4`.** The next thing is set 4 of the same exercise. As drawn, "up next" means "the next *exercise*", which is a look-ahead nobody acts on mid-set and which contradicts the set counter directly above it. Replace with the conditional Then line (§5.1).
2. **§8.3 compact and §7.5 — the "ready"/`GO` state.** Not deliverable (P4). §8.2's constraint table correctly identifies `Text(timerInterval:)` as the countdown solution but omits the corollary that *no other view can change at T=0*, and §7.5's "Live Activity switches to the 'ready' state" was written on that omission. Add P4 to §8.2 and delete the ready state.
3. **§8.3 minimal — "a filled ring showing rest progress".** iOS has no determinate circular `ProgressView`, and a custom ring cannot animate without updates (P5). Replace per §4.4.
4. **§8.4 — the FINISHED state.** The app cannot know the workout is over, because `+ Add Set` always exists and ghost counts are suggestions (§7.3). Auto-declaring completion is the app deciding for you, which Principle 8 forbids. Replace with a nil pointer rendering plus a `Finish` deep link (§7 row 13).
5. **§8.3 expanded, resting — no tick.** Finishing rest early costs two taps, and if the T=0 update never lands the surface is unusable. The tick must be live in both phases (§5.4).
6. **§15 vs §8.5 — a direct contradiction.** §15: "the write always uses current state." §8.5: "what you see is what gets written." When the island is stale these disagree. Resolve as §6.1: values from the intent, target re-resolved, mismatch is a no-op refresh. Amend the §15 row.
7. **§8.5 / §10.2 — the `Island tick logs:` setting.** As specified it applies to the island only, which means the island and the in-app ghost row can display different numbers for the same set. That breaks the §7.3 guarantee that "the Previous column and the ghost values come from the same source" and it breaks Principle 5's consistency promise. Either cut the setting, or promote it to a global ghost-source preference. My recommendation is to cut it: §7.3's priority (history first) is already the right answer, and Q11 is asking a question the ghost resolver has effectively already settled.
8. **§8.3 — `⟨ same as last time ⟩`.** On the island the values are not a suggestion; they are the literal payload of the button. Rendering them as a hedge undercuts the one property that makes the tick safe to press without looking. Principle 5's grey/black distinction is an *in-app* rule about ghost rows versus logged rows; the island has no logged rows to contrast against. The payload renders as fact, in `.primary`, always.
9. **§8 never states P2** — that compact and minimal cannot host a button. This matters: G6 ("never unlock the phone mid-workout") is delivered by the **Lock Screen**, not by the Dynamic Island. §8.1's "glance, tap, rest, repeat" should say so, and §1.2's "you glance at the Dynamic Island, see your target, tap a tick" is describing something the platform does not permit.
10. **§8.7's ContentState list is incomplete** for what §8.3 draws: it omits the planned-set total, a payload-known flag, drop position, and the deep-link focus target. §8 is the document M6 gets built from; see §8 above for the full shape.
11. **Three code prerequisites §8 does not mention** — planned set count, rest state, and pending drop rows all live in SwiftUI `@State` and are invisible to the widget process. See §9. None is large, but M6 cannot start until all three land, and two of them fix existing in-app defects independently of the island (§9.2 rest state, §9.3 unticked drop rows lost on relaunch).
12. **§8.4's claim that "there is exactly one implementation of next set" is now true but incomplete.** M5 shipped `WorkoutEngine.nextSet`, built for the rest notification's one-line "Next:" string. The island needs an address, not a sentence, and it needs to resolve cold. Five deltas, all shared improvements — §3.1.

---

## 12. Accessibility

Per §17: full VoiceOver on all four presentations, Dynamic Type to XXL without truncation, targets ≥44×44pt, never colour alone.

| Element | VoiceOver |
|---|---|
| Lock Screen container | `Push Day A. Seated Cable Row, set 3 of 4. Target 12 kilograms, 6 reps.` |
| Same, in a superset | `Push Day A. Superset A, exercise 1 of 2, Incline Dumbbell Press, round 3 of 4. Target 15 kilograms, 10 reps. Then A2 Cable Fly.` |
| Same, mid drop chain | `Seated Cable Row, drop set 1 of 2. Target 10 kilograms, 8 reps.` |
| Countdown | `Resting, 1 minute 42 seconds remaining.` |
| ✓ | `Log this set` — button |
| Skip | `Skip rest` — button |
| `⋯` | `Adjust this set` — button |
| `Open` | `Open in Rerack to enter values` — button |
| `Finish` | `Finish workout` — button |
| Compact / minimal | Full sentence label; the region is one accessibility element |

The superset badge never carries meaning by colour alone — `A1` is text, and the accent capsule is decoration. The tick fills solid on press as well as tinting, matching §17's in-app rule.

Dynamic Type: at accessibility sizes each presentation drops from the bottom of the §2 ladder upward. In practice the Lock Screen loses the routine name first, then `⋯`, then the Then line; the payload and tick never drop. The compact island loses its trailing token before its leading one.
