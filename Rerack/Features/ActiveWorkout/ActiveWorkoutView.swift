import SwiftUI
import SwiftData
import AudioToolbox

/// PRD §7 (M3), plus the new mid-workout superset behaviour: exercises can
/// be grouped explicitly (§7.4 "Add to superset") or auto-detected from
/// alternating between two unfinished exercises (new — see
/// `recordForDetection` below). Both sit alongside, not instead of,
/// pre-planned grouping from the routine editor (M2).
struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var restingExerciseID: UUID?
    @State private var restStartedAt: Date?
    @State private var restAdjustSeconds = 0
    /// Set the moment the app leaves the foreground while a rest period is
    /// running (§ scenePhase handling below), reset whenever rest starts or
    /// clears. Distinguishes "this rest completed while backgrounded" (system
    /// notification's job, plus the one-time permission ask, §7.5) from
    /// "completed while foregrounded" (haptic/sound/banner) at expiry time.
    @State private var restStartedWhileBackgrounded = false
    /// Content of the currently-scheduled/most-recently-fired rest
    /// notification, kept around only so the foreground banner (§7.5) can
    /// show the exact same "Next: …" line rather than recomputing it.
    @State private var pendingRestContent: RestNotificationScheduler.Content?

    @State private var restCompleteBanner: RestNotificationScheduler.Content?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var isShowingNotificationPrimer = false

    @State private var showingAddExercise = false
    @State private var showingDiscardConfirm = false
    @State private var showingEmptyFinishConfirm = false
    @State private var showingSummary = false
    @State private var detailExercise: Exercise?

    // MARK: Superset auto-detection (in-memory only — a soft nudge feature,
    // not data; losing it on a force-quit mid-detection is harmless, see
    // PRD §21-style reasoning on transient vs. persisted state)
    @State private var recentHistory: [UUID] = []
    @State private var pendingPairs: Set<PairKey> = []
    @State private var declinedPairs: Set<PairKey> = []

    /// Held separately from `isShowingSupersetPrompt` on purpose. SwiftUI
    /// sets an alert's `isPresented` binding back to false *before* running
    /// the tapped button's action — so if the pair lived in the same state
    /// the binding clears, "No" would find it already nil and silently fail
    /// to record the decline. Keeping identity here means the button action
    /// always has something to act on.
    @State private var promptedPair: PairKey?
    @State private var promptedNames: (current: String, previous: String) = ("", "")
    @State private var isShowingSupersetPrompt = false

    private let restTickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct PairKey: Hashable {
        let a: UUID
        let b: UUID
        init(_ x: UUID, _ y: UUID) {
            if x.uuidString < y.uuidString { a = x; b = y } else { a = y; b = x }
        }
    }

    private var sortedExercises: [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var restingExercise: WorkoutExercise? {
        guard let restingExerciseID else { return nil }
        return sortedExercises.first { $0.id == restingExerciseID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsHeader

                    if let restingExercise, let restStartedAt {
                        RestTimerBar(
                            restStartedAt: restStartedAt,
                            durationSeconds: max(restDuration(for: restingExercise) + restAdjustSeconds, 15),
                            onSkip: { clearRest() },
                            onAdjust: { delta in
                                restAdjustSeconds += delta
                                rescheduleRestNotification(for: restingExercise)
                            }
                        )
                        .padding(.horizontal)
                    }

                    ForEach(sortedExercises) { workoutExercise in
                        VStack(spacing: 0) {
                            ExerciseCardView(
                                workoutExercise: workoutExercise,
                                allExercises: sortedExercises,
                                ghosts: ghosts(for: workoutExercise),
                                currentRestSeconds: restDuration(for: workoutExercise),
                                onSetCompleted: handleCompleted,
                                onSetUncompleted: handleUncompleted,
                                onDropAdded: handleDropAdded,
                                onGroupWith: { partner in group(workoutExercise, with: partner) },
                                onUngroup: { ungroup(workoutExercise) },
                                onRemove: { remove(workoutExercise) },
                                onShowDetail: { detailExercise = workoutExercise.exercise },
                                onSetRestConfig: { seconds, saveAsDefault in
                                    applyRestConfig(workoutExercise, seconds: seconds, saveAsDefault: saveAsDefault)
                                }
                            )
                            Divider()
                        }
                        .padding(.horizontal)
                    }

                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingDiscardConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish", action: attemptFinish)
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerSheet { exercise in addExercise(exercise) }
            }
            .sheet(item: $detailExercise) { exercise in
                ExerciseQuickDetailView(exercise: exercise)
            }
            .fullScreenCover(isPresented: $showingSummary) {
                WorkoutSummaryView(workout: workout) {
                    showingSummary = false
                    onFinish()
                }
            }
            .confirmationDialog(
                "Discard this workout? This can't be undone.",
                isPresented: $showingDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Workout", role: .destructive) {
                    clearRest()
                    onDiscard()
                }
                Button("Keep Going", role: .cancel) {}
            }
            // Discard-empty guard: a "Finish" with nothing logged would
            // otherwise save an empty workout row forever cluttering history.
            .confirmationDialog(
                "This workout has no completed sets.",
                isPresented: $showingEmptyFinishConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Workout", role: .destructive) {
                    clearRest()
                    onDiscard()
                }
                Button("Keep Going", role: .cancel) {}
            }
            .alert("Superset?", isPresented: $isShowingSupersetPrompt) {
                Button("Yes", action: confirmSupersetPrompt)
                Button("No", role: .cancel, action: declineSupersetPrompt)
            } message: {
                Text("Group \(promptedNames.previous) and \(promptedNames.current) as a superset? Rest gets skipped between them.")
            }
            // PRD §7.5: asked once, the first time rest completes while
            // backgrounded — see `RestNotificationScheduler.handleBackgroundedCompletion`.
            .alert("Allow Notifications?", isPresented: $isShowingNotificationPrimer) {
                Button("Not Now", role: .cancel) {}
                Button("Enable") { RestNotificationScheduler.requestSystemPermission() }
            } message: {
                Text("Rerack can let you know when your rest timer ends, even while your phone is locked.")
            }
            .overlay(alignment: .top) {
                if let restCompleteBanner {
                    RestCompleteBanner(content: restCompleteBanner, onDismiss: dismissRestCompleteBanner)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: restCompleteBanner != nil)
            .onReceive(restTickTimer) { _ in checkRestExpiry() }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    if restingExerciseID != nil { restStartedWhileBackgrounded = true }
                case .active:
                    checkRestExpiry()
                    // Still resting after that check means expiry hasn't
                    // happened yet — we're back watching it in foreground, so
                    // a brief earlier background dip shouldn't make the
                    // *eventual* completion look like a backgrounded one.
                    if restingExerciseID != nil { restStartedWhileBackgrounded = false }
                default:
                    break
                }
            }
        }
        .onAppear { applyIdleTimerSetting() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Header

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: workout.startedAt, by: 1)) { context in
                Text(formattedDuration(context.date.timeIntervalSince(workout.startedAt)))
                    .font(.title2.monospacedDigit())
            }
            HStack(spacing: 12) {
                Label("\(Int(totalVolume)) kg", systemImage: "scalemass")
                Label("\(totalSets) sets", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var allCompletedSets: [SetLog] {
        sortedExercises.flatMap { $0.sets ?? [] }.filter(\.isCompleted)
    }

    private var totalVolume: Double {
        allCompletedSets.reduce(0) { $0 + $1.setVolumeKg }
    }

    private var totalSets: Int { allCompletedSets.count }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Ghosts & rest duration

    private func ghosts(for workoutExercise: WorkoutExercise) -> [GhostSet] {
        guard let exercise = workoutExercise.exercise else { return [] }
        let routineExercise = workout.routine?.exercises?.first { $0.exercise?.id == exercise.id }
        return GhostSetResolver.ghostSets(
            for: exercise,
            routineExercise: routineExercise,
            excludingWorkoutID: workout.id,
            context: modelContext
        )
    }

    /// PRD §7.5 hierarchy: per-exercise-in-workout override → per-exercise
    /// default → global default (falls back to 180s if no profile exists —
    /// onboarding, which would create one, hasn't shipped yet).
    private func restDuration(for workoutExercise: WorkoutExercise) -> Int {
        if let override = workoutExercise.restSecondsUsed { return override }
        if let exerciseDefault = workoutExercise.exercise?.defaultRestSeconds { return exerciseDefault }
        return currentProfile()?.defaultRestSeconds ?? 180
    }

    private func currentProfile() -> UserProfile? {
        (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    // MARK: - Set completion

    private func handleCompleted(_ workoutExercise: WorkoutExercise, _ setLog: SetLog, hasPendingDrop: Bool) {
        recalculateCachedStats()
        recordForDetection(workoutExercise)

        // PRD §10.2 "Auto-start rest timer" — off means sets simply don't
        // start a rest period (see the `UserProfile.autoStartRestTimer` doc
        // comment for why there's no manual-start fallback in V1).
        let autoStartEnabled = currentProfile()?.autoStartRestTimer ?? true
        if autoStartEnabled, WorkoutEngine.shouldStartRest(after: workoutExercise, hasPendingDrop: hasPendingDrop, allExercises: sortedExercises) {
            let now = Date()
            setLog.restStartedAt = now
            restingExerciseID = workoutExercise.id
            restStartedAt = now
            restAdjustSeconds = 0
            restStartedWhileBackgrounded = false
            scheduleRestNotification(for: workoutExercise)
        }
        try? modelContext.save()
    }

    private func handleUncompleted(_ workoutExercise: WorkoutExercise, _ setLog: SetLog) {
        recalculateCachedStats()
        if restingExerciseID == workoutExercise.id {
            clearRest()
        }
        try? modelContext.save()
    }

    /// §7.9: a drop was just added under a set on this exercise — the chain
    /// isn't over, so any rest already ticking for it is stale. Unlike the
    /// superset round check, this fires regardless of round state: an open
    /// drop chain always wins (`shouldStartRest`'s `hasPendingDrop` gate is
    /// the same rule at tick time; this is its mirror at add-time, for the
    /// case where the tick already started a timer before the drop existed).
    private func handleDropAdded(_ workoutExercise: WorkoutExercise) {
        if restingExerciseID == workoutExercise.id {
            clearRest()
        }
    }

    private func recalculateCachedStats() {
        workout.cachedVolumeKg = totalVolume
        workout.cachedSetCount = totalSets
        workout.cachedRepCount = allCompletedSets.reduce(0) { $0 + $1.reps }
    }

    /// The single funnel every rest-ending path goes through — un-tick,
    /// skip, drop-added, exercise removed, natural expiry, finish, discard.
    /// Cancelling the pending notification here (rather than at each call
    /// site) is what makes that cancellation airtight: nothing can end a
    /// rest period without also going through this.
    private func clearRest() {
        restingExerciseID = nil
        restStartedAt = nil
        restAdjustSeconds = 0
        restStartedWhileBackgrounded = false
        pendingRestContent = nil
        RestNotificationScheduler.cancelPending()
    }

    private func checkRestExpiry() {
        guard let restingExercise, let restStartedAt else { return }
        let duration = max(restDuration(for: restingExercise) + restAdjustSeconds, 15)
        guard Date() >= restStartedAt.addingTimeInterval(TimeInterval(duration)) else { return }

        let completedWhileBackgrounded = restStartedWhileBackgrounded
        let content = pendingRestContent ?? .init(durationSeconds: duration, nextLine: nil)
        clearRest()

        if completedWhileBackgrounded {
            // The system notification (if permission was already granted)
            // already alerted the user while the app was away — this
            // foreground moment is instead the one PRD-specified trigger for
            // asking permission, so future rests can notify too.
            RestNotificationScheduler.handleBackgroundedCompletion {
                isShowingNotificationPrimer = true
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if currentProfile()?.restTimerSoundEnabled ?? true {
                AudioServicesPlaySystemSound(1005) // PRD §10.2 "Rest timer sound"
            }
            presentRestCompleteBanner(content)
        }
    }

    // MARK: - Rest notification scheduling (§7.5)

    private func scheduleRestNotification(for workoutExercise: WorkoutExercise) {
        guard let restStartedAt else { return }
        let duration = max(restDuration(for: workoutExercise) + restAdjustSeconds, 15)
        let fireDate = restStartedAt.addingTimeInterval(TimeInterval(duration))
        let next = WorkoutEngine.nextSet(after: workoutExercise, allExercises: sortedExercises, ghostsProvider: ghosts(for:))
        let nextLine = next.map { "\($0.exerciseName) · Set \($0.setNumber) · \(formattedWeight($0.weightKg)) kg × \($0.reps)" }
        let content = RestNotificationScheduler.Content(durationSeconds: duration, nextLine: nextLine)
        pendingRestContent = content
        RestNotificationScheduler.schedule(fireAt: fireDate, content: content)
    }

    /// PRD §7.5: adjusting the timer (−15s/+15s) or changing the exercise's
    /// rest config mid-rest both change the fire time, so the stale
    /// notification is cancelled (inside `schedule`) and a fresh one takes
    /// its place — not just cancelled outright.
    private func rescheduleRestNotification(for workoutExercise: WorkoutExercise) {
        guard restingExerciseID == workoutExercise.id else { return }
        scheduleRestNotification(for: workoutExercise)
    }

    private func presentRestCompleteBanner(_ content: RestNotificationScheduler.Content) {
        bannerDismissTask?.cancel()
        restCompleteBanner = content
        bannerDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            restCompleteBanner = nil
        }
    }

    private func dismissRestCompleteBanner() {
        bannerDismissTask?.cancel()
        restCompleteBanner = nil
    }

    /// PRD §7.4/§7.5: sets either the per-exercise-in-workout override or the
    /// per-exercise default, depending on the "save as default" toggle in
    /// `RestDurationPickerSheet`. Saving as default clears the workout-scoped
    /// override so the hierarchy (§7.5) falls through to the value just set,
    /// rather than leaving a stale override that would shadow it.
    private func applyRestConfig(_ workoutExercise: WorkoutExercise, seconds: Int, saveAsDefault: Bool) {
        if saveAsDefault {
            workoutExercise.exercise?.defaultRestSeconds = seconds
            workoutExercise.restSecondsUsed = nil
        } else {
            workoutExercise.restSecondsUsed = seconds
        }
        try? modelContext.save()
        rescheduleRestNotification(for: workoutExercise)
    }

    /// PRD §10.2 "Keep screen awake" — scoped to this screen only, per the
    /// task's explicit instruction; `onDisappear` always turns it back off
    /// regardless of the setting so leaving the workout can never strand the
    /// idle timer disabled for the rest of the app.
    private func applyIdleTimerSetting() {
        UIApplication.shared.isIdleTimerDisabled = currentProfile()?.keepScreenAwakeDuringWorkout ?? true
    }

    // MARK: - Superset auto-detection (new)

    /// PRD §7.8.1. If you leave an exercise mid-way and log a set on a
    /// different one, that's a "maybe superset?" — asked once.
    ///
    /// **"No" is final.** A declined pair goes into `declinedPairs` and is
    /// never asked about, and never auto-grouped, again for the rest of this
    /// workout. Only a prompt that went *unanswered* (dismissed without a
    /// button, or never surfaced because another prompt was already up) is
    /// eligible for the auto-group-on-second-alternation path.
    ///
    /// Pre-planned and explicitly-grouped pairs are never re-evaluated here —
    /// this only ever looks at pairs that are currently ungrouped.
    private func recordForDetection(_ workoutExercise: WorkoutExercise) {
        recentHistory.append(workoutExercise.id)
        if recentHistory.count > 6 { recentHistory.removeFirst() }

        guard workoutExercise.supersetGroup == nil else { return }
        guard let previousID = recentHistory.dropLast().last(where: { $0 != workoutExercise.id }) else { return }
        guard let previous = sortedExercises.first(where: { $0.id == previousID }),
              previous.supersetGroup == nil else { return }

        let key = PairKey(workoutExercise.id, previous.id)
        guard !declinedPairs.contains(key) else { return }
        guard hasIncompleteExpectedSets(previous) else { return }

        if pendingPairs.contains(key) {
            SupersetGrouping.group(workoutExercise, with: previous, among: sortedExercises)
            pendingPairs.remove(key)
            return
        }

        pendingPairs.insert(key)
        // Don't stack prompts — if one is already up, this pair stays pending
        // and takes the auto-group path on its next alternation.
        guard !isShowingSupersetPrompt else { return }
        promptedPair = key
        promptedNames = (
            current: workoutExercise.exercise?.name ?? "this one",
            previous: previous.exercise?.name ?? "that exercise"
        )
        isShowingSupersetPrompt = true
    }

    /// "Left mid-way" needs a known expected count to compare against —
    /// from history or a routine target. With neither (a brand-new exercise
    /// in an empty workout), there's nothing to judge "incomplete" against,
    /// so detection deliberately stays quiet rather than guessing.
    private func hasIncompleteExpectedSets(_ workoutExercise: WorkoutExercise) -> Bool {
        let expected = ghosts(for: workoutExercise).count
        guard expected > 0 else { return false }
        // Top-level sets only (§7.9). Drops are continuations of a set, not
        // sets of their own — counting them here would make a drop chain look
        // like progress against the expected count and wrongly suppress the
        // superset prompt. Same reasoning as `WorkoutEngine.completedCount`.
        let completed = WorkoutEngine.completedCount(workoutExercise)
        return completed > 0 && completed < expected
    }

    private func confirmSupersetPrompt() {
        guard let key = promptedPair else { return }
        if let a = sortedExercises.first(where: { $0.id == key.a }),
           let b = sortedExercises.first(where: { $0.id == key.b }) {
            SupersetGrouping.group(a, with: b, among: sortedExercises)
        }
        pendingPairs.remove(key)
        promptedPair = nil
    }

    /// "No" means no. The pair is removed from the pending set *and* added to
    /// `declinedPairs`, so no amount of further alternation will group it —
    /// the user answered, and the app doesn't get to overrule that.
    private func declineSupersetPrompt() {
        guard let key = promptedPair else { return }
        pendingPairs.remove(key)
        declinedPairs.insert(key)
        promptedPair = nil
    }

    // MARK: - Exercises

    private func addExercise(_ exercise: Exercise) {
        let workoutExercise = WorkoutExercise(orderIndex: sortedExercises.count, exercise: exercise)
        modelContext.insert(workoutExercise)
        workoutExercise.workout = workout
    }

    private func remove(_ workoutExercise: WorkoutExercise) {
        let group = workoutExercise.supersetGroup
        if restingExerciseID == workoutExercise.id { clearRest() }
        modelContext.delete(workoutExercise)
        if let group { SupersetGrouping.dissolveIfSingle(group, among: sortedExercises) }
    }

    private func group(_ a: WorkoutExercise, with b: WorkoutExercise) {
        SupersetGrouping.group(a, with: b, among: sortedExercises)
    }

    private func ungroup(_ workoutExercise: WorkoutExercise) {
        SupersetGrouping.ungroup(workoutExercise, among: sortedExercises)
    }

    // MARK: - Lifecycle

    /// PRD §9.4 discard-empty guard: finishing with zero completed sets
    /// offers to discard rather than saving an empty `Workout` row.
    private func attemptFinish() {
        if totalSets == 0 {
            showingEmptyFinishConfirm = true
        } else {
            finish()
        }
    }

    private func finish() {
        // A pending rest notification would otherwise fire for a workout
        // that's already over, pointing at a "next set" nobody's doing.
        clearRest()
        workout.endedAt = Date()
        recalculateCachedStats()
        // PRD §13.4: PR detection runs once, here, so Best Session Volume
        // sees the whole session. §9.3: the routine baseline updates from
        // the same completed data. Both run before the summary screen shows
        // so its 🏆 flags and "N new records" line (§9.4) are already
        // correct — the summary's own "Done" only persists the optional
        // photo/gym/tags/notes fields added on that screen, not these numbers.
        PersonalRecordDetector.detect(workout: workout, context: modelContext)
        updateRoutineBaseline()
        try? modelContext.save()
        showingSummary = true
    }

    /// PRD §9.3 "baseline loop," step 4: when `updateValuesOnFinish` is on,
    /// the routine's own `RoutineSetTemplate` targets are overwritten with
    /// what was actually completed, so next time's ghosts (§7.3) come from a
    /// template that already matches reality. `lastPerformedAt` updates
    /// unconditionally — that's a plain fact about the routine, independent
    /// of whether it self-updates its targets.
    private func updateRoutineBaseline() {
        guard let routine = workout.routine else { return }
        routine.lastPerformedAt = Date()
        guard routine.updateValuesOnFinish else { return }

        for workoutExercise in sortedExercises {
            guard let exerciseID = workoutExercise.exercise?.id,
                  let routineExercise = routine.exercises?.first(where: { $0.exercise?.id == exerciseID })
            else { continue }

            // Top-level sets only — drop chains (§7.9) are a workout-time
            // concept the routine editor never plans for.
            let completed = (workoutExercise.sets ?? [])
                .filter { $0.isCompleted && $0.parentSetID == nil }
                .sorted { $0.orderIndex < $1.orderIndex }
            var templates = (routineExercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }

            for (index, setLog) in completed.enumerated() {
                if index < templates.count {
                    templates[index].targetWeightKg = setLog.addedWeightKg
                    templates[index].targetReps = setLog.reps
                    templates[index].setType = setLog.setType
                } else {
                    let template = RoutineSetTemplate(
                        orderIndex: index,
                        targetWeightKg: setLog.addedWeightKg,
                        targetReps: setLog.reps,
                        setType: setLog.setType
                    )
                    modelContext.insert(template)
                    template.routineExercise = routineExercise
                    templates.append(template)
                }
            }

            // Fewer sets performed than planned — the routine self-heals
            // toward reality (§9.3), so the surplus targets go with it
            // rather than lingering as a stale plan for sets that didn't
            // happen this time.
            if templates.count > completed.count {
                for extra in templates[completed.count...] {
                    modelContext.delete(extra)
                }
            }
        }
    }
}
