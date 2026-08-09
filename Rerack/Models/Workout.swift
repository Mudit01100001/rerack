import Foundation
import SwiftData

/// PRD §7.7, §9.4, §11. `endedAt == nil` means the workout is still live —
/// that's the flag crash recovery checks for on launch.
@Model
final class Workout {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?

    var location: String?
    /// Multi-select chips (PRD §9.4 / Q2) — e.g. ["Push", "Short on time"].
    var tags: [String] = []
    var notes: String?

    /// PRD §9.4: the one photo in the product, taken at the top of the
    /// finish-flow summary. Filename only; the image lives in the app's
    /// container, never uploaded. `nil` until a photo is attached.
    var photoFilename: String?

    /// Snapshot of Apple Health bodyweight at workout time (PRD §13.1) —
    /// captured once, not re-read later, for the same reason
    /// `SetLog.effectiveLoadKg` is snapshotted rather than recomputed.
    var bodyweightKg: Double?

    // Denormalised so history lists don't aggregate thousands of sets on
    // scroll (PRD §11). Recomputed on every set mutation once M3 exists.
    var cachedVolumeKg: Double = 0
    var cachedSetCount: Int = 0
    var cachedRepCount: Int = 0

    /// Snapshot of the routine's flag *at the time of this workout* (PRD
    /// §9.3) — so toggling the setting later doesn't retroactively rewrite
    /// historical graphs and PRs.
    var trackedAsProgress: Bool = true

    /// Frozen at creation so the name survives the routine being deleted
    /// (PRD §15) even though `routine` below goes nil via `.nullify`.
    var routineNameSnapshot: String?

    /// M6 §9.2. The absolute instant the current rest period ends, or `nil`
    /// when nothing is resting. Persisted rather than held as view `@State`
    /// because three separate consumers must agree on it: the in-app bar, the
    /// local notification (§7.5), and the Live Activity countdown running in
    /// the widget process — which cannot see `@State` at all (M6 §P8). Storing
    /// the *end* instant rather than a start-plus-duration also makes
    /// `±15s` adjustments and §17's ±1s accuracy fall out for free.
    var restEndsAt: Date?

    /// The instant rest began. Only the in-app progress bar needs it (a
    /// `ProgressView(timerInterval:)` needs both ends of the range); the
    /// island's countdown and the notification care only about `restEndsAt`.
    var restStartedAt: Date?

    /// Which exercise's rest is running — needed to render the bar under the
    /// right card and to cancel rest when that exercise is removed (§7 row 26).
    var restingExerciseID: UUID?

    /// True once rest has begun for the currently-resting set. Distinct from
    /// `restEndsAt != nil` because rest stays "active" for a beat after the
    /// countdown hits zero (P4: no update can fire at T=0 from a suspended
    /// app), and the app repairs the state on next foreground rather than
    /// pretending the transition happened on time.
    var isResting: Bool { restEndsAt != nil }

    var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]? = []

    init(title: String, routine: Routine? = nil, startedAt: Date = Date()) {
        self.title = title
        self.routine = routine
        self.routineNameSnapshot = routine?.name
        self.startedAt = startedAt
        self.trackedAsProgress = routine?.trackAsProgress ?? true
    }

    var isLive: Bool { endedAt == nil }
}

/// PRD §7.8: `supersetGroup` mirrors `RoutineExercise.supersetGroup` but is
/// captured independently per workout, so ad-hoc mid-workout superset
/// changes (§7.4 "Add to superset") don't have to write back to the routine.
@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var supersetGroup: String?
    var notes: String?
    var restSecondsUsed: Int?

    /// M6 §9.1. How many set rows this exercise is *planning* to do — the
    /// persisted twin of what `ExerciseCardView` used to compute as
    /// `ghosts.count + extraRows`. `nil` means "however many ghosts resolve",
    /// so a routine-driven exercise needs no value written until `+ Add Set`
    /// is tapped. Persisted because the widget process can't see view state
    /// (M6 §P8) and because `extraRows` as `@State` was silently lost every
    /// time the card was torn down — an in-app defect in its own right.
    var plannedSetCount: Int?

    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.workoutExercise)
    var sets: [SetLog]? = []

    init(orderIndex: Int, exercise: Exercise, supersetGroup: String? = nil) {
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.supersetGroup = supersetGroup
    }
}

extension WorkoutExercise: SupersetGroupable {}

/// PRD §7.2, §7.9, §13.1. A `SetLog` row is only ever created when a set is
/// *completed* — ghost rows are pure view state and never touch the database
/// (§7.3), so every row here represents something that actually happened.
@Model
final class SetLog {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var setTypeRaw: String = SetType.normal.rawValue

    /// Non-nil marks this as a drop set, chained off the parent's `id` (§7.9).
    var parentSetID: UUID?

    /// What's actually on the bar/stack — i.e. what you'd read off the pins,
    /// not counting bodyweight.
    var addedWeightKg: Double = 0

    /// `(bodyweight × bodyweightFactor) + addedWeightKg`, snapshotted at
    /// completion time per PRD §13.1 and never recomputed — so a later change
    /// in bodyweight can't silently rewrite historical volume.
    var effectiveLoadKg: Double = 0

    var reps: Int = 0

    /// PRD §18 Q8: always a manual self-report, never inferred. Blank is
    /// always valid. UI hidden by default (Settings toggle) even though the
    /// field exists from M1.
    var rpe: Double?

    var isCompleted: Bool = false
    var completedAt: Date?

    /// Wall-clock anchor for the rest timer (PRD §7.5) — computed from this
    /// timestamp rather than a running counter, so backgrounding or the app
    /// being killed can't cause drift.
    var restStartedAt: Date?

    var prFlagsRaw: Int = 0

    /// PRD §17 — `app` vs `live_activity`. Meaningful once M6 ships; every
    /// set logged before then is naturally `app`.
    var loggedFromRaw: String = LoggedFrom.app.rawValue

    var workoutExercise: WorkoutExercise?

    init(orderIndex: Int, setType: SetType = .normal, addedWeightKg: Double = 0, reps: Int = 0) {
        self.orderIndex = orderIndex
        self.setTypeRaw = setType.rawValue
        self.addedWeightKg = addedWeightKg
        self.effectiveLoadKg = addedWeightKg
        self.reps = reps
    }

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .normal }
        set { setTypeRaw = newValue.rawValue }
    }

    var prFlags: PRFlags {
        get { PRFlags(rawValue: prFlagsRaw) }
        set { prFlagsRaw = newValue.rawValue }
    }

    var loggedFrom: LoggedFrom {
        get { LoggedFrom(rawValue: loggedFromRaw) ?? .app }
        set { loggedFromRaw = newValue.rawValue }
    }

    /// PRD §13.2.
    var setVolumeKg: Double { effectiveLoadKg * Double(reps) }
}
