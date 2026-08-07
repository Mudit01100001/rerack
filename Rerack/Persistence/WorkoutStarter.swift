import Foundation
import SwiftData

/// PRD §7.7: "Starting a routine creates a Workout row with startedAt = now
/// immediately. Everything from there is an incremental save." SetLog rows
/// are deliberately NOT created here — only WorkoutExercise shells, one per
/// planned exercise — since a set only becomes real data once it's actually
/// completed (§7.3).
@MainActor
enum WorkoutStarter {
    @discardableResult
    static func startEmptyWorkout(context: ModelContext) -> Workout {
        let workout = Workout(title: "Workout")
        context.insert(workout)
        return workout
    }

    @discardableResult
    static func start(routine: Routine, context: ModelContext) -> Workout {
        let workout = Workout(title: routine.name, routine: routine)
        context.insert(workout)

        let routineExercises = (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        for routineExercise in routineExercises {
            guard let exercise = routineExercise.exercise else { continue }
            let workoutExercise = WorkoutExercise(
                orderIndex: routineExercise.orderIndex,
                exercise: exercise,
                supersetGroup: routineExercise.supersetGroup
            )
            workoutExercise.restSecondsUsed = routineExercise.restSecondsOverride
            context.insert(workoutExercise)
            workoutExercise.workout = workout
        }

        return workout
    }
}
