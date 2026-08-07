import Foundation

/// PRD §7.5/§7.8/§7.9: pure rules for how superset rounds and drop chains
/// affect the rest timer. Deliberately simple for this first cut — it
/// assumes group members are doing roughly the same number of sets, which is
/// true for the common case and the one worth getting right first; real
/// usage will show whether the uneven-set-count edge case needs its own rule.
@MainActor
enum WorkoutEngine {
    static func groupMembers(of workoutExercise: WorkoutExercise, in all: [WorkoutExercise]) -> [WorkoutExercise] {
        guard let group = workoutExercise.supersetGroup else { return [workoutExercise] }
        return all.filter { $0.supersetGroup == group }
    }

    /// Top-level sets only (§7.9): a set plus however many drops chained off
    /// it is one round for superset purposes, not one round per drop —
    /// otherwise a drop chain would make this exercise's count outrun a
    /// partner who did the same number of "real" sets.
    static func completedCount(_ workoutExercise: WorkoutExercise) -> Int {
        (workoutExercise.sets ?? []).filter { $0.isCompleted && $0.parentSetID == nil }.count
    }

    /// Rest starts immediately for a standalone exercise with no open drop
    /// chain. Two independent gates, both must clear:
    /// - **Drop chain (§7.9):** `hasPendingDrop` is true whenever the set
    ///   just ticked has an uncommitted drop row already waiting under it —
    ///   the chain isn't over, so rest is suppressed regardless of anything
    ///   else. This is the caller's job to compute, since pending drops are
    ///   pure view state (§7.3-style — never in the database until ticked)
    ///   and this engine only sees persisted data.
    /// - **Superset round (§7.8):** suppressed until every other member of
    ///   the group has caught up to (or passed) this exercise's completed
    ///   top-level-set count — i.e. the round is actually over, not just one
    ///   member's turn.
    /// Composes correctly for a drop chain inside a superset member: the
    /// group's round can only be judged "over" once each member's own drop
    /// chains have also closed, because a set with an open chain doesn't
    /// count until it's ticked in the first place.
    static func shouldStartRest(
        after workoutExercise: WorkoutExercise,
        hasPendingDrop: Bool,
        allExercises: [WorkoutExercise]
    ) -> Bool {
        guard !hasPendingDrop else { return false }
        let members = groupMembers(of: workoutExercise, in: allExercises)
        guard members.count > 1 else { return true }
        let myCount = completedCount(workoutExercise)
        return !members.contains { $0.id != workoutExercise.id && completedCount($0) < myCount }
    }

    /// PRD §7.5: what the rest-complete notification and in-app banner call
    /// "Next" — the same round-robin order described in §7.8.1, computed
    /// fresh rather than stored so there's one source of truth for it.
    /// `ghostsProvider` is the caller's existing `GhostSetResolver` pipeline,
    /// so "how many sets does this exercise have" and "what's the target
    /// weight/reps" agree with what the set rows themselves show.
    struct NextSetPointer {
        let exerciseName: String
        let setNumber: Int
        let weightKg: Double
        let reps: Int
    }

    static func nextSet(
        after workoutExercise: WorkoutExercise,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let members = groupMembers(of: workoutExercise, in: allExercises)
        guard members.count > 1 else {
            if let mine = pointer(for: workoutExercise, ghostsProvider: ghostsProvider) { return mine }
            return nextInSequence(after: workoutExercise.orderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider)
        }

        // Round-robin: walk forward from this exercise's position in the
        // group, wrapping around. A member with no sets left (§15 "superset
        // member runs out of sets") is simply skipped — `pointer(for:)`
        // returns nil for it and the loop moves on to the next member.
        let ordered = members.sorted { $0.orderIndex < $1.orderIndex }
        guard let startIndex = ordered.firstIndex(where: { $0.id == workoutExercise.id }) else { return nil }
        for offset in 1...ordered.count {
            let candidate = ordered[(startIndex + offset) % ordered.count]
            if let found = pointer(for: candidate, ghostsProvider: ghostsProvider) { return found }
        }
        // Whole group is out of sets — fall through to whatever comes next
        // in the workout after the group's last member.
        let groupMaxOrderIndex = ordered.map(\.orderIndex).max() ?? workoutExercise.orderIndex
        return nextInSequence(after: groupMaxOrderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider)
    }

    /// The next set within a single exercise, if it has any expected sets
    /// left. "Expected" is the ghost/target count — an exercise with no
    /// history and no routine target has no known length, so it's treated as
    /// having nothing left rather than guessed at.
    private static func pointer(
        for workoutExercise: WorkoutExercise,
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let ghosts = ghostsProvider(workoutExercise)
        let completed = completedCount(workoutExercise)
        guard completed < ghosts.count else { return nil }
        let ghost = ghosts[completed]
        return NextSetPointer(
            exerciseName: workoutExercise.exercise?.name ?? "Exercise",
            setNumber: completed + 1,
            weightKg: ghost.weightKg,
            reps: ghost.reps
        )
    }

    private static func nextInSequence(
        after orderIndex: Int,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let upcoming = allExercises
            .filter { $0.orderIndex > orderIndex }
            .sorted { $0.orderIndex < $1.orderIndex }
        for candidate in upcoming {
            if let found = pointer(for: candidate, ghostsProvider: ghostsProvider) { return found }
        }
        return nil
    }
}
