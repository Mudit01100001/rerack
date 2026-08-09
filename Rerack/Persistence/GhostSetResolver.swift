import Foundation
import SwiftData

/// PRD §7.3. A ghost set is view-only — never written to the database until
/// approved or edited — so this resolver just answers "what would the ghost
/// values be," leaving the caller to decide what to do with them.
struct GhostSet {
    let weightKg: Double
    let reps: Int
    /// PRD §7.9 closing bullet: the drop chain that followed this set last
    /// time it was performed, in order. Empty when it wasn't a drop-chain
    /// parent (or when there's no history to reconstruct one from, e.g. the
    /// routine-template fallback). Never itself nested — one parent with
    /// drops chained off it, not a tree, same shape as `SetLog.parentSetID`.
    var drops: [GhostSet] = []
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
            let allSets = last.sets ?? []
            // Top-level only — drop sets are reattached below as `.drops` on
            // their parent, never as their own flat entry in this list. They
            // used to leak in here unfiltered, which both misrepresented a
            // drop as an ordinary next set *and* shifted every ghost after it
            // by one position — the actual mechanism behind the "known gap."
            let topLevel = allSets
                .filter { $0.isCompleted && $0.parentSetID == nil }
                .sorted { $0.orderIndex < $1.orderIndex }
            if !topLevel.isEmpty {
                return topLevel.map { top in
                    let drops = allSets
                        .filter { $0.isCompleted && $0.parentSetID == top.id }
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { GhostSet(weightKg: $0.addedWeightKg, reps: $0.reps) }
                    return GhostSet(weightKg: top.addedWeightKg, reps: top.reps, drops: drops)
                }
            }
        }
        if let templates = routineExercise?.setTemplates?.sorted(by: { $0.orderIndex < $1.orderIndex }), !templates.isEmpty {
            // Routine templates have no parent/child linkage (§7.9 chains are
            // a history-only concept), so there's nothing to reconstruct a
            // drop chain from here — `drops` stays empty, same as before.
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
