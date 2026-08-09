import Foundation
// `Activity` predates Sendable and doesn't conform, but every use here stays
// on the MainActor-owned instance — preconcurrency downgrades the false alarm.
@preconcurrency import ActivityKit
import SwiftData

/// M6. Owns the one `Activity` a live workout projects onto the Lock Screen
/// and Dynamic Island. Start/refresh/end all funnel through here so the
/// content state is composed in exactly one place (M6 §8) — the widget is a
/// dumb renderer, and an intent running with the app force-quit uses this
/// same composer, so the island can never disagree with the app about what
/// a set is called.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var activity: Activity<WorkoutActivityAttributes>?

    // MARK: - Lifecycle

    /// Creates the activity if the system allows one and none exists yet for
    /// this workout. Safe to call on every appearance of the active-workout
    /// screen — crash recovery and device reboot (§7 row 35) both land here.
    func startIfNeeded(
        workout: Workout,
        exercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return } // §7 row 37: no repeat prompt, no fallback loss
        if activity == nil {
            // Adopt an activity that survived this process being relaunched.
            activity = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.workoutID == workout.id }
        }
        guard activity == nil else {
            refresh(workout: workout, exercises: exercises, ghostsProvider: ghostsProvider)
            return
        }

        let attributes = WorkoutActivityAttributes(
            workoutID: workout.id,
            workoutTitle: workout.routineNameSnapshot ?? workout.title,
            startedAt: workout.startedAt
        )
        let state = Self.contentState(for: workout, exercises: exercises, ghostsProvider: ghostsProvider)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(8 * 3600))
        )
    }

    func refresh(
        workout: Workout,
        exercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) {
        guard let activity else { return }
        let state = Self.contentState(for: workout, exercises: exercises, ghostsProvider: ghostsProvider)
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(8 * 3600)))
        }
    }

    /// §7 rows 28–30: finish, discard, and abandoned-workout resolution all
    /// end immediately. There is no FINISHED presentation (M6 §11 item 4).
    func end() {
        guard let activity else {
            // The app may have relaunched since the activity was created.
            for orphan in Activity<WorkoutActivityAttributes>.activities {
                Task { await orphan.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Content composition (M6 §8)

    static func contentState(
        for workout: Workout,
        exercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> WorkoutActivityAttributes.ContentState {
        let phase: WorkoutActivityAttributes.ContentState.Phase = workout.isResting ? .resting : .logging

        guard let pointer = WorkoutEngine.nextSet(in: workout, ghostsProvider: ghostsProvider) else {
            // §7 rows 2 and 13: nothing planned remains (or nothing exists
            // yet). Rest may still be running off the final tick.
            var state = WorkoutActivityAttributes.ContentState.allLogged
            state.phase = phase
            state.restEndsAt = workout.restEndsAt
            state.restStartedAt = workout.restStartedAt
            state.positionLabel = exercises.isEmpty ? "No exercises yet" : "All planned sets logged"
            return state
        }

        let payload: WorkoutActivityAttributes.ContentState.Payload
        if pointer.isPayloadKnown {
            let loadType = exercises
                .first { $0.id == pointer.workoutExerciseID }?
                .exercise?.loadType ?? .external
            // M6 §5.3 `repsOnly`: a bodyweight exercise with no bar weight
            // renders `10 reps`, and the tick writes 0 kg — which §7.2
            // allows and §13.1 makes correct.
            payload = (loadType == .bodyweight && pointer.weightKg == 0)
                ? .repsOnly(reps: pointer.reps)
                : .known(weightKg: pointer.weightKg, reps: pointer.reps)
        } else {
            payload = .unknown
        }

        return WorkoutActivityAttributes.ContentState(
            phase: phase,
            restEndsAt: workout.restEndsAt,
            restStartedAt: workout.restStartedAt,
            exerciseImageName: ExerciseArtwork.assetName(for: pointer.exerciseName),
            workoutExerciseID: pointer.workoutExerciseID,
            setIndex: pointer.setIndex,
            exerciseName: pointer.exerciseName,
            supersetLabel: pointer.supersetLabel,
            positionLabel: pointer.positionLabel,
            compactToken: pointer.compactToken,
            payload: payload,
            thenLine: WorkoutEngine.thenLine(after: pointer, allExercises: exercises, ghostsProvider: ghostsProvider)
        )
    }
}

/// The ghost pipeline, buildable from any `ModelContext` — the view has its
/// own copy of this wiring; intents performing in the background (M6 §P7)
/// use this one. Both call the same `GhostSetResolver`, so the island's
/// payload and the in-app ghost row can't come from different sources.
@MainActor
enum WorkoutGhosts {
    static func provider(for workout: Workout, context: ModelContext) -> (WorkoutExercise) -> [GhostSet] {
        { workoutExercise in
            guard let exercise = workoutExercise.exercise else { return [] }
            let routineExercise = workout.routine?.exercises?.first { $0.exercise?.id == exercise.id }
            return GhostSetResolver.ghostSets(
                for: exercise,
                routineExercise: routineExercise,
                excludingWorkoutID: workout.id,
                context: context
            )
        }
    }
}
