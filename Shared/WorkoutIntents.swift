import Foundation
import AppIntents
import SwiftData

/// M6 §6.1 — the tick. A `LiveActivityIntent` performs **in the app's
/// process**, relaunching it in the background if it was force-quit (§P7),
/// which is what makes logging from the Lock Screen work with zero servers.
///
/// The write semantics resolve the §15-vs-§8.5 contradiction (M6 §11 item 6):
/// the *values* come from this intent, byte for byte as displayed (WYSIWYG);
/// the *target* is re-resolved from the store at perform time. If the pointer
/// has moved — the set was already logged or edited in-app — nothing is
/// written, and the refreshed state the user sees is the honest outcome.
struct LogSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Set"
    /// The whole point is logging without unlocking (§G6).
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    @Parameter(title: "Workout ID") var workoutID: String
    @Parameter(title: "Exercise ID") var workoutExerciseID: String
    @Parameter(title: "Set Index") var setIndex: Int
    @Parameter(title: "Weight (kg)") var weightKg: Double
    @Parameter(title: "Reps") var reps: Int

    init() {}

    init(workoutID: UUID, workoutExerciseID: UUID, setIndex: Int, weightKg: Double, reps: Int) {
        self.workoutID = workoutID.uuidString
        self.workoutExerciseID = workoutExerciseID.uuidString
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContainerFactory.shared.mainContext
        guard let workoutUUID = UUID(uuidString: workoutID),
              let exerciseUUID = UUID(uuidString: workoutExerciseID),
              let workout = fetchWorkout(id: workoutUUID, context: context),
              workout.isLive
        else { return .result() }

        let exercises = (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let ghostsProvider = WorkoutGhosts.provider(for: workout, context: context)

        // §6.1 step 1–2: re-resolve, and only write on an exact match.
        guard let pointer = WorkoutEngine.nextSet(in: workout, ghostsProvider: ghostsProvider),
              pointer.workoutExerciseID == exerciseUUID,
              pointer.setIndex == setIndex,
              let workoutExercise = exercises.first(where: { $0.id == exerciseUUID })
        else {
            // §6.1 step 3 / §7 row 14: the pointer moved. Write nothing;
            // push the corrected truth.
            LiveActivityController.shared.refresh(workout: workout, exercises: exercises, ghostsProvider: ghostsProvider)
            return .result()
        }

        let setLog: SetLog
        if let existingID = pointer.setLogID,
           let existing = (workoutExercise.sets ?? []).first(where: { $0.id == existingID }) {
            setLog = existing
        } else {
            setLog = SetLog(orderIndex: setIndex)
            context.insert(setLog)
            setLog.workoutExercise = workoutExercise
        }
        setLog.addedWeightKg = weightKg
        setLog.reps = reps
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        setLog.effectiveLoadKg = EffectiveLoad.kg(
            addedWeightKg: weightKg,
            loadType: workoutExercise.exercise?.loadType ?? .external,
            bodyweightFactor: workoutExercise.exercise?.bodyweightFactor ?? 0,
            bodyweightKg: workout.bodyweightKg,
            useBodyweightInVolume: profile?.useBodyweightInVolume ?? true
        )
        setLog.isCompleted = true
        setLog.completedAt = Date()
        // §17: the most interesting number in the product once M6 ships.
        setLog.loggedFrom = .liveActivity

        recalculateCachedStats(for: workout)

        // Same two-gate rest rule as an in-app tick (§7.5/§7.8/§7.9).
        let autoStart = profile?.autoStartRestTimer ?? true
        if autoStart, WorkoutEngine.shouldStartRest(after: setLog, in: workoutExercise, allExercises: exercises) {
            let now = Date()
            let duration = max(restDuration(for: workoutExercise, profile: profile), 15)
            setLog.restStartedAt = now
            workout.restingExerciseID = workoutExercise.id
            workout.restStartedAt = now
            workout.restEndsAt = now.addingTimeInterval(TimeInterval(duration))
            scheduleRestNotification(for: workoutExercise, in: workout, exercises: exercises, duration: duration, ghostsProvider: ghostsProvider)
        }

        try? context.save()
        LiveActivityController.shared.refresh(workout: workout, exercises: exercises, ghostsProvider: ghostsProvider)
        return .result()
    }

    @MainActor
    private func fetchWorkout(id: UUID, context: ModelContext) -> Workout? {
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    @MainActor
    private func recalculateCachedStats(for workout: Workout) {
        let completed = (workout.exercises ?? []).flatMap { $0.sets ?? [] }.filter(\.isCompleted)
        workout.cachedVolumeKg = completed.reduce(0) { $0 + $1.setVolumeKg }
        workout.cachedSetCount = completed.count
        workout.cachedRepCount = completed.reduce(0) { $0 + $1.reps }
    }

    /// §7.5 hierarchy — per-workout override → exercise default → profile default.
    @MainActor
    private func restDuration(for workoutExercise: WorkoutExercise, profile: UserProfile?) -> Int {
        if let override = workoutExercise.restSecondsUsed { return override }
        if let exerciseDefault = workoutExercise.exercise?.defaultRestSeconds { return exerciseDefault }
        return profile?.defaultRestSeconds ?? 180
    }

    @MainActor
    private func scheduleRestNotification(
        for workoutExercise: WorkoutExercise,
        in workout: Workout,
        exercises: [WorkoutExercise],
        duration: Int,
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) {
        guard let fireDate = workout.restEndsAt else { return }
        let next = WorkoutEngine.nextSet(after: workoutExercise, allExercises: exercises, ghostsProvider: ghostsProvider)
        let nextLine = next.map { "\($0.exerciseName) · \($0.positionLabel) · \(WorkoutEngine.formattedPayload(weightKg: $0.weightKg, reps: $0.reps))" }
        RestNotificationScheduler.schedule(
            fireAt: fireDate,
            content: .init(durationSeconds: duration, nextLine: nextLine)
        )
    }
}

/// M6 §7 row 16. Ends the rest period early; never writes a set.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    @Parameter(title: "Workout ID") var workoutID: String

    init() {}

    init(workoutID: UUID) {
        self.workoutID = workoutID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContainerFactory.shared.mainContext
        guard let workoutUUID = UUID(uuidString: workoutID) else { return .result() }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutUUID })
        guard let workout = (try? context.fetch(descriptor))?.first, workout.isLive else { return .result() }

        workout.restingExerciseID = nil
        workout.restStartedAt = nil
        workout.restEndsAt = nil
        RestNotificationScheduler.cancelPending()
        try? context.save()

        let exercises = (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        LiveActivityController.shared.refresh(
            workout: workout,
            exercises: exercises,
            ghostsProvider: WorkoutGhosts.provider(for: workout, context: context)
        )
        return .result()
    }
}
