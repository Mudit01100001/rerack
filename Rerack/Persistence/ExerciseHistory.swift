import Foundation
import SwiftData

/// PRD §9.2. One session's worth of an exercise, already aggregated — the
/// Exercise Detail screen's Summary graph, History list, and lifetime strip
/// all read from this rather than each re-deriving totals from raw sets.
struct ExerciseSession: Identifiable {
    let id: UUID
    let workoutID: UUID
    let workoutTitle: String
    let date: Date
    /// Top-level sets in order, each with its drop chain attached (§7.9), so
    /// History can render the grouping intact.
    let sets: [SetLog]
    let dropsByParentID: [UUID: [SetLog]]
    let supersetGroup: String?

    /// PRD §9.2's five graph metrics.
    let heaviestWeightKg: Double
    let bestOneRepMaxKg: Double?
    let bestSetVolumeKg: Double
    let sessionVolumeKg: Double
    let totalReps: Int
}

@MainActor
enum ExerciseHistory {
    /// Every completed session containing `exercise`, newest first.
    ///
    /// `trackedAsProgress == false` sessions (§9.3 — deload weeks, testing
    /// days) are excluded here, because every caller of this is a
    /// progress-flavoured view: graphs, PRs, lifetime stats. They still
    /// exist in the workout log and in the CSV export; they just don't move
    /// the trend lines. History (the raw list) uses `includeUntracked: true`.
    static func sessions(
        for exercise: Exercise,
        includeUntracked: Bool = false,
        context: ModelContext
    ) -> [ExerciseSession] {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.exercise?.id == exerciseID }
        )
        guard let workoutExercises = try? context.fetch(descriptor) else { return [] }

        return workoutExercises.compactMap { workoutExercise -> ExerciseSession? in
            guard let workout = workoutExercise.workout, workout.endedAt != nil else { return nil }
            guard includeUntracked || workout.trackedAsProgress else { return nil }

            let completed = (workoutExercise.sets ?? []).filter(\.isCompleted)
            guard !completed.isEmpty else { return nil }

            let topLevel = completed
                .filter { $0.parentSetID == nil }
                .sorted { $0.orderIndex < $1.orderIndex }
            let drops = Dictionary(grouping: completed.filter { $0.parentSetID != nil }) { $0.parentSetID! }

            // §13.4: Heaviest Weight and Best 1RM exclude drop sets; the two
            // volume metrics include them. Same split as PersonalRecordDetector.
            let nonDrop = completed.filter { $0.setType != .drop }

            return ExerciseSession(
                id: workoutExercise.id,
                workoutID: workout.id,
                workoutTitle: workout.title,
                date: workout.startedAt,
                sets: topLevel,
                dropsByParentID: drops.mapValues { $0.sorted { $0.orderIndex < $1.orderIndex } },
                supersetGroup: workoutExercise.supersetGroup,
                heaviestWeightKg: nonDrop.filter { $0.reps >= 1 }.map(\.effectiveLoadKg).max() ?? 0,
                bestOneRepMaxKg: completed.compactMap {
                    OneRepMax.estimate(weightKg: $0.effectiveLoadKg, reps: $0.reps, setType: $0.setType)
                }.max(),
                bestSetVolumeKg: completed.map(\.setVolumeKg).max() ?? 0,
                sessionVolumeKg: completed.reduce(0) { $0 + $1.setVolumeKg },
                totalReps: completed.reduce(0) { $0 + $1.reps }
            )
        }
        .sorted { $0.date > $1.date }
    }

    struct LifetimeStats {
        let sessionCount: Int
        let setCount: Int
        let repCount: Int
        let volumeKg: Double
        let firstPerformed: Date?
        let lastPerformed: Date?
    }

    static func lifetimeStats(from sessions: [ExerciseSession]) -> LifetimeStats {
        LifetimeStats(
            sessionCount: sessions.count,
            setCount: sessions.reduce(0) { $0 + $1.sets.count },
            repCount: sessions.reduce(0) { $0 + $1.totalReps },
            volumeKg: sessions.reduce(0) { $0 + $1.sessionVolumeKg },
            firstPerformed: sessions.last?.date,
            lastPerformed: sessions.first?.date
        )
    }

    static func personalRecords(for exercise: Exercise, context: ModelContext) -> [PRType: PersonalRecord] {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID }
        )
        guard let records = try? context.fetch(descriptor) else { return [:] }
        // Keep the highest per type — PersonalRecordDetector only ever writes
        // on a strict improvement, so the newest is also the best, but
        // reducing on value makes this independent of that guarantee.
        return records.reduce(into: [:]) { result, record in
            if let existing = result[record.type], existing.valueKg >= record.valueKg { return }
            result[record.type] = record
        }
    }
}
