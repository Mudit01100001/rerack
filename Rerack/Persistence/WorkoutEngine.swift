import Foundation

/// PRD §7.5/§7.8: pure rules for how a superset round affects the rest
/// timer. Deliberately simple for this first cut — it assumes group members
/// are doing roughly the same number of sets, which is true for the common
/// case and the one worth getting right first; real usage will show whether
/// the uneven-set-count edge case needs its own rule.
@MainActor
enum WorkoutEngine {
    static func groupMembers(of workoutExercise: WorkoutExercise, in all: [WorkoutExercise]) -> [WorkoutExercise] {
        guard let group = workoutExercise.supersetGroup else { return [workoutExercise] }
        return all.filter { $0.supersetGroup == group }
    }

    static func completedCount(_ workoutExercise: WorkoutExercise) -> Int {
        (workoutExercise.sets ?? []).filter(\.isCompleted).count
    }

    /// Rest starts immediately for a standalone exercise. Inside a superset,
    /// rest is suppressed until every other member of the group has caught
    /// up to (or passed) this exercise's completed-set count — i.e. the
    /// round is actually over, not just one member's turn.
    static func shouldStartRest(after workoutExercise: WorkoutExercise, allExercises: [WorkoutExercise]) -> Bool {
        let members = groupMembers(of: workoutExercise, in: allExercises)
        guard members.count > 1 else { return true }
        let myCount = completedCount(workoutExercise)
        return !members.contains { $0.id != workoutExercise.id && completedCount($0) < myCount }
    }
}
