import Foundation
import SwiftData

/// PRD §9.1, §13.1. Enums are stored as raw strings (SwiftData-safe across
/// OS versions) with typed computed accessors on top, rather than storing
/// the enum directly — keeps the persisted schema stable even if an enum's
/// underlying representation ever changes.
@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var equipmentRaw: String = Equipment.other.rawValue
    var primaryMuscleRaw: String = Muscle.fullBody.rawValue
    var secondaryMusclesRaw: [String] = []
    var loadTypeRaw: String = LoadType.external.rawValue

    /// See PRD §13.1's table (pull-up 1.0, push-up 0.64, inverted row 0.5, etc.).
    /// Meaningless when `loadType == .external`; left at 0 in that case.
    var bodyweightFactor: Double = 0

    var isCustom: Bool = false
    var defaultRestSeconds: Int?

    /// Free-form how-to text for user-created exercises. Catalogue entries
    /// use `instructions` below instead.
    var howToBody: String?

    /// Ordered how-to steps (§9.2 Tab 3), merged from free-exercise-db at
    /// M11 — public domain, so there's no attribution obligation and no
    /// licence to propagate (§23.2).
    ///
    /// Empty for the ~70 catalogue entries free-exercise-db has no
    /// equivalent for, and for custom exercises. The tab renders whatever
    /// exists rather than claiming coverage it doesn't have.
    var instructions: [String] = []

    /// Which run of the bundled catalogue seed (Resources/ExerciseCatalog.json)
    /// introduced this row. `nil` for user-created custom exercises. Lets
    /// `ExerciseSeeder` add new built-ins in a future app update without
    /// re-inserting or duplicating ones already seeded — see PRD §9.1.
    var catalogVersion: Int?

    var createdAt: Date = Date()

    /// PRD §15: exercises are never hard-deleted once they have history —
    /// they're hidden from the library and library search but preserved in
    /// every workout, PR, and export that already references them.
    var isArchived: Bool = false

    // Raw data (workouts, routines) must never silently disappear if an
    // Exercise row goes away, so those relationships use `.deny` rather than
    // `.cascade` — deleting an Exercise that's actually been used fails loudly
    // instead of quietting deleting history. Derived data (PersonalRecord) is
    // safe to cascade since it can be recomputed.
    @Relationship(deleteRule: .deny, inverse: \RoutineExercise.exercise)
    var routineExercises: [RoutineExercise]? = []

    @Relationship(deleteRule: .deny, inverse: \WorkoutExercise.exercise)
    var workoutExercises: [WorkoutExercise]? = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]? = []

    init(
        name: String,
        equipment: Equipment,
        primaryMuscle: Muscle,
        secondaryMuscles: [Muscle] = [],
        loadType: LoadType = .external,
        bodyweightFactor: Double = 0,
        isCustom: Bool = false,
        defaultRestSeconds: Int? = nil,
        catalogVersion: Int? = nil,
        instructions: [String] = []
    ) {
        self.instructions = instructions
        self.name = name
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.secondaryMusclesRaw = secondaryMuscles.map(\.rawValue)
        self.loadTypeRaw = loadType.rawValue
        self.bodyweightFactor = bodyweightFactor
        self.isCustom = isCustom
        self.defaultRestSeconds = defaultRestSeconds
        self.catalogVersion = catalogVersion
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var primaryMuscle: Muscle {
        get { Muscle(rawValue: primaryMuscleRaw) ?? .fullBody }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    var secondaryMuscles: [Muscle] {
        get { secondaryMusclesRaw.compactMap { Muscle(rawValue: $0) } }
        set { secondaryMusclesRaw = newValue.map(\.rawValue) }
    }

    var loadType: LoadType {
        get { LoadType(rawValue: loadTypeRaw) ?? .external }
        set { loadTypeRaw = newValue.rawValue }
    }
}
