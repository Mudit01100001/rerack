import SwiftUI
import SwiftData

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

    @State private var restingExerciseID: UUID?
    @State private var restStartedAt: Date?
    @State private var restAdjustSeconds = 0

    @State private var showingAddExercise = false
    @State private var showingDiscardConfirm = false
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
                            onAdjust: { delta in restAdjustSeconds += delta }
                        )
                        .padding(.horizontal)
                    }

                    ForEach(sortedExercises) { workoutExercise in
                        VStack(spacing: 0) {
                            ExerciseCardView(
                                workoutExercise: workoutExercise,
                                allExercises: sortedExercises,
                                ghosts: ghosts(for: workoutExercise),
                                onSetCompleted: handleCompleted,
                                onSetUncompleted: handleUncompleted,
                                onGroupWith: { partner in group(workoutExercise, with: partner) },
                                onUngroup: { ungroup(workoutExercise) },
                                onRemove: { remove(workoutExercise) },
                                onShowDetail: { detailExercise = workoutExercise.exercise }
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
                    Button("Finish", action: finish)
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerSheet { exercise in addExercise(exercise) }
            }
            .sheet(item: $detailExercise) { exercise in
                ExerciseQuickDetailView(exercise: exercise)
            }
            .confirmationDialog(
                "Discard this workout? This can't be undone.",
                isPresented: $showingDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Workout", role: .destructive, action: onDiscard)
                Button("Keep Going", role: .cancel) {}
            }
            .alert("Superset?", isPresented: $isShowingSupersetPrompt) {
                Button("Yes", action: confirmSupersetPrompt)
                Button("No", role: .cancel, action: declineSupersetPrompt)
            } message: {
                Text("Group \(promptedNames.previous) and \(promptedNames.current) as a superset? Rest gets skipped between them.")
            }
            .onReceive(restTickTimer) { _ in checkRestExpiry() }
        }
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
        let profiles = try? modelContext.fetch(FetchDescriptor<UserProfile>())
        return profiles?.first?.defaultRestSeconds ?? 180
    }

    // MARK: - Set completion

    private func handleCompleted(_ workoutExercise: WorkoutExercise, _ setLog: SetLog) {
        recalculateCachedStats()
        recordForDetection(workoutExercise)

        if WorkoutEngine.shouldStartRest(after: workoutExercise, allExercises: sortedExercises) {
            let now = Date()
            setLog.restStartedAt = now
            restingExerciseID = workoutExercise.id
            restStartedAt = now
            restAdjustSeconds = 0
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

    private func recalculateCachedStats() {
        workout.cachedVolumeKg = totalVolume
        workout.cachedSetCount = totalSets
        workout.cachedRepCount = allCompletedSets.reduce(0) { $0 + $1.reps }
    }

    private func clearRest() {
        restingExerciseID = nil
        restStartedAt = nil
        restAdjustSeconds = 0
    }

    private func checkRestExpiry() {
        guard let restingExercise, let restStartedAt else { return }
        let duration = max(restDuration(for: restingExercise) + restAdjustSeconds, 15)
        guard Date() >= restStartedAt.addingTimeInterval(TimeInterval(duration)) else { return }
        clearRest()
        // Full notification/banner handling lands in M5 — this haptic is a
        // harmless preview of "rest is over" while the app is foregrounded.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        let completed = (workoutExercise.sets ?? []).filter(\.isCompleted).count
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

    private func finish() {
        workout.endedAt = Date()
        recalculateCachedStats()
        try? modelContext.save()
        onFinish()
    }
}
