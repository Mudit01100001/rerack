import Foundation
import SwiftData

/// PRD §9.3.
@Model
final class RoutineFolder {
    var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Routine.folder)
    var routines: [Routine]? = []

    init(name: String, orderIndex: Int = 0) {
        self.name = name
        self.orderIndex = orderIndex
    }
}

/// PRD §9.3. Muscle groups shown on a routine's card are *derived* from its
/// exercises' primary muscles at render time — deliberately not stored here,
/// so they can never go stale when an exercise is swapped (§9.3).
@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    var orderIndex: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastPerformedAt: Date?

    /// PRD §9.3 routine settings. Both default on; both toggleable per routine.
    var trackAsProgress: Bool = true
    var updateValuesOnFinish: Bool = true

    var folder: RoutineFolder?

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise]? = []

    /// Nullify, not cascade: deleting a routine must never delete the
    /// workouts performed under it (PRD §15 — "past workouts survive with
    /// routine_name frozen"). `Workout.routineNameSnapshot` keeps the name
    /// readable even after this relationship goes nil.
    @Relationship(deleteRule: .nullify, inverse: \Workout.routine)
    var workouts: [Workout]? = []

    init(name: String, notes: String? = nil, folder: RoutineFolder? = nil, orderIndex: Int = 0) {
        self.name = name
        self.notes = notes
        self.folder = folder
        self.orderIndex = orderIndex
    }
}

/// PRD §7.8: `supersetGroup` (e.g. "A", "B") links exercises that round-robin
/// together with rest suppressed between them. `nil` means a standalone
/// exercise. Position within the group follows `orderIndex`.
@Model
final class RoutineExercise {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var supersetGroup: String?
    var intraSupersetRestSeconds: Int = 0
    var restSecondsOverride: Int?
    var notes: String?

    var routine: Routine?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \RoutineSetTemplate.routineExercise)
    var setTemplates: [RoutineSetTemplate]? = []

    init(orderIndex: Int, exercise: Exercise, supersetGroup: String? = nil) {
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.supersetGroup = supersetGroup
    }
}

extension RoutineExercise: SupersetGroupable {}

/// PRD §9.3: the routine's *targets*. These seed ghost values the first time
/// a routine is run; after that, ghosts come from actual history (§7.3) and
/// these targets self-update on finish if `updateValuesOnFinish` is on.
@Model
final class RoutineSetTemplate {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var targetWeightKg: Double?
    var targetReps: Int?
    var setTypeRaw: String = SetType.normal.rawValue

    var routineExercise: RoutineExercise?

    init(orderIndex: Int, targetWeightKg: Double? = nil, targetReps: Int? = nil, setType: SetType = .normal) {
        self.orderIndex = orderIndex
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.setTypeRaw = setType.rawValue
    }

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .normal }
        set { setTypeRaw = newValue.rawValue }
    }
}
