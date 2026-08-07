import Foundation
import SwiftData

/// PRD §7.3. A ghost set is view-only — never written to the database until
/// approved or edited — so this resolver just answers "what would the ghost
/// values be," leaving the caller to decide what to do with them.
struct GhostSet {
    let weightKg: Double
    let reps: Int
}

@MainActor
enum GhostSetResolver {
    /// PRD §7.3 source priority: most recent workout that actually completed
    /// this exercise, regardless of which routine it was under. Filtered and
    /// sorted in Swift rather than via a SwiftData sort descriptor through a
    /// relationship, which keeps the fetch predicate simple and reliable.
    static func lastCompletedWorkoutExercise(
        for exercise: Exercise,
        excludingWorkoutID: UUID,
        context: ModelContext
    ) -> WorkoutExercise? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.exercise?.id == exerciseID }
        )
        guard let candidates = try? context.fetch(descriptor) else { return nil }
        return candidates
            .filter { $0.workout?.endedAt != nil && $0.workout?.id != excludingWorkoutID }
            .sorted { ($0.workout?.startedAt ?? .distantPast) > ($1.workout?.startedAt ?? .distantPast) }
            .first
    }

    /// The full ordered ghost list for an exercise in the current workout —
    /// from history if any exists, else from the routine's targets, else empty.
    static func ghostSets(
        for exercise: Exercise,
        routineExercise: RoutineExercise?,
        excludingWorkoutID: UUID,
        context: ModelContext
    ) -> [GhostSet] {
        if let last = lastCompletedWorkoutExercise(for: exercise, excludingWorkoutID: excludingWorkoutID, context: context) {
            let sets = (last.sets ?? []).filter(\.isCompleted).sorted { $0.orderIndex < $1.orderIndex }
            if !sets.isEmpty {
                return sets.map { GhostSet(weightKg: $0.addedWeightKg, reps: $0.reps) }
            }
        }
        if let templates = routineExercise?.setTemplates?.sorted(by: { $0.orderIndex < $1.orderIndex }), !templates.isEmpty {
            return templates.map { GhostSet(weightKg: $0.targetWeightKg ?? 0, reps: $0.targetReps ?? 0) }
        }
        return []
    }

    /// PRD §7.3 fallback rule: if the current index runs past the ghost
    /// list's length, repeat the last ghost set rather than going blank.
    static func ghostSet(at index: Int, in ghosts: [GhostSet]) -> GhostSet? {
        guard !ghosts.isEmpty else { return nil }
        return index < ghosts.count ? ghosts[index] : ghosts.last
    }
}
