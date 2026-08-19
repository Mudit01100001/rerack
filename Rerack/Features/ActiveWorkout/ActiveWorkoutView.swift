import SwiftUI
import SwiftData
import AudioToolbox
import WidgetKit

/// PRD §7 (M3), plus the new mid-workout superset behaviour: exercises can
/// be grouped explicitly (§7.4 "Add to superset") or auto-detected from
/// alternating between two unfinished exercises (new — see
/// `recordForDetection` below). Both sit alongside, not instead of,
/// pre-planned grouping from the routine editor (M2).
struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    let onFinish: () -> Void
    let onDiscard: () -> Void
    /// Parks the session and returns to the rest of the app. The workout
    /// stays live; the banner is the way back.
    let onMinimize: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.unitPreference) private var unit

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
    /// Item 11: set when the session's exercise list no longer matches the
    /// template it started from, so the user gets to say what that means.
    @State private var showingDivergencePrompt = false
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var isShowingNotificationPrimer = false

    @State private var showingAddExercise = false
    @State private var showingWorkoutSettings = false
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

    /// M6 §9.2: rest lives on the `Workout` row, not in view state, so the
    /// widget process and a background intent see the same instant this bar
    /// does.
    private var restingExercise: WorkoutExercise? {
        guard let id = workout.restingExerciseID else { return nil }
        return sortedExercises.first { $0.id == id }
    }

    /// One funnel for every "the island is now out of date" moment, so no
    /// call site has to remember the three arguments (M6 §8's composer takes
    /// the same inputs everywhere).
    private func refreshActivity() {
        LiveActivityController.shared.refresh(
            workout: workout,
            exercises: sortedExercises,
            ghostsProvider: ghosts(for:)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsHeader

                    if let restingExercise,
                       let restStartedAt = workout.restStartedAt,
                       let restEndsAt = workout.restEndsAt {
                        RestTimerBar(
                            restStartedAt: restStartedAt,
                            restEndsAt: restEndsAt,
                            onSkip: {
                                Haptics.play(.timerSkipped)
                                clearRest()
                            },
                            onSetRemaining: { seconds in
                                Haptics.play(.timerAdjusted)
                                setRest(remainingSeconds: seconds, for: restingExercise)
                            }
                        )
                        .padding(.horizontal)
                    }

                    ForEach(sortedExercises) { workoutExercise in
                        card(for: workoutExercise)
                            .padding(.horizontal)
                    }

                    // Editing the routine mid-workout (§7.4) — sits below
                    // every card because that's where you are when you
                    // realise you want one more movement.
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .dsFont(DS.TypeScale.body, relativeTo: .subheadline, weight: .medium)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .dsCard()
                    .padding(.horizontal)

                    workoutActions
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            // Grouped grey behind the cards — without it the cards are the
            // same colour as the page and the grouping does nothing.
            // Item 8: the keyboard used to have exactly one exit — the
            // collapse chevron, which also parked the workout. Swiping the
            // list now dismisses it, which is what every other iOS list does.
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            // Build 5 item G: a number pad has no Return key, so without this
            // there was no way to close the keyboard short of scrolling it
            // away or tapping the chevron. `resignFirstResponder` rather than
            // a stored `@FocusState` because the field that's focused could
            // be any set row's weight or reps box, and this dismisses
            // whichever one it is without the row needing to expose its own
            // focus binding up to this view. Known iOS 17 quirk: a keyboard
            // toolbar can fail to appear the *first* time a field inside a
            // `fullScreenCover` gets focus and only show up on the second —
            // moving this screen to a `.sheet` (item A) sidesteps it, since
            // the bug is specific to the cover presentation style.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Minimise, not discard. Leaving a live session used to
                    // mean destroying it, which made "step away for a second"
                    // and "throw away the last 40 minutes" the same gesture.
                    // Discard now lives at the bottom of the screen, where
                    // you have to mean it.
                    Button {
                        onMinimize()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimise workout")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish", action: attemptFinish)
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerSheet { exercise in addExercise(exercise) }
            }
            .sheet(isPresented: $showingWorkoutSettings) {
                WorkoutSettingsSheet(workout: workout)
            }
            .sheet(item: $detailExercise) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .fullScreenCover(isPresented: $showingSummary) {
                WorkoutSummaryView(workout: workout) {
                    showingSummary = false
                    onFinish()
                }
            }
            // `.alert`, not `.confirmationDialog`. A confirmation dialog
            // anchors itself to the control that opened it and renders with a
            // caret pointing back at the toolbar button, which reads as a
            // tooltip rather than a decision and put a destructive action
            // under an easily-mis-tapped popover. An alert is centred, modal,
            // and gives Cancel equal weight.
            // Item 11. Two choices, no third "update the template" — the
            // user was explicit that saving a *new* workout and keeping the
            // *old* one are the whole decision, and that carrying weights
            // between sessions is a separate concept handled by ghost sets
            // (§7.3), not by this prompt.
            .alert("This session doesn't match the plan", isPresented: $showingDivergencePrompt) {
                Button("Save as New Workout") {
                    saveAsNewWorkout()
                    finish()
                }
                Button("Keep the Old Workout") {
                    finish()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You changed the exercises in \(workout.title). Save what you did as a new workout, or leave the original as it is?")
            }
            .alert("Discard this workout?", isPresented: $showingDiscardConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    clearRest()
                    LiveActivityController.shared.end() // §7 row 29
                    onDiscard()
                }
            } message: {
                Text("Everything you've logged in this session will be deleted. This can't be undone.")
            }
            // Discard-empty guard: a "Finish" with nothing logged would
            // otherwise save an empty workout row forever cluttering history.
            .alert("Nothing logged yet", isPresented: $showingEmptyFinishConfirm) {
                Button("Keep Going", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    clearRest()
                    LiveActivityController.shared.end() // §7 row 29
                    onDiscard()
                }
            } message: {
                Text("This workout has no completed sets, so there's nothing to save.")
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
                    if workout.restingExerciseID != nil { restStartedWhileBackgrounded = true }
                case .active:
                    checkRestExpiry()
                    // Still resting after that check means expiry hasn't
                    // happened yet — we're back watching it in foreground, so
                    // a brief earlier background dip shouldn't make the
                    // *eventual* completion look like a backgrounded one.
                    if workout.restingExerciseID != nil { restStartedWhileBackgrounded = false }
                default:
                    break
                }
            }
        }
        .onAppear { applyIdleTimerSetting() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task { await captureBodyweightSnapshot() }
        // §8.6/§7 rows 1, 31, 35: created when the workout screen first
        // appears, re-adopted after relaunch, recreated after reboot.
        .task {
            LiveActivityController.shared.startIfNeeded(workout: workout, exercises: sortedExercises, ghostsProvider: ghosts(for:))
        }
    }

    /// PRD §13.1: read once per workout and frozen on the `Workout` row, so
    /// every set ticked in this session shares one bodyweight — and a weigh-in
    /// halfway through can't make set 4 heavier than set 3 for no reason.
    /// Runs on the *first* appearance only: a re-entered workout (crash
    /// recovery, §7.7, or reopening from the cross-tab banner) keeps the value
    /// it started with.
    private func captureBodyweightSnapshot() async {
        guard workout.bodyweightKg == nil, workout.isLive else { return }
        guard let kg = await HealthKitManager.bodyweightKg(asOf: workout.startedAt) else { return }
        workout.bodyweightKg = kg
    }

    /// Session-level actions, at the end of the scroll rather than in the
    /// toolbar. Discard is destructive and irreversible, so it lives where
    /// you have to deliberately scroll past your whole workout to reach it —
    /// never adjacent to the tick you're tapping forty times a session.
    private var workoutActions: some View {
        HStack(spacing: DS.Space.sm) {
            actionChip("Settings", systemImage: "gearshape", tint: .secondary) {
                showingWorkoutSettings = true
            }
            actionChip("Discard", systemImage: "trash", tint: .red) {
                showingDiscardConfirm = true
            }
        }
    }

    /// Hand-rolled rather than `.buttonStyle(.bordered)`: the system style
    /// picks its own corner radius, which is what made these two disagree
    /// with the cards above them.
    private func actionChip(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: DS.Radius.medium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercise cards

    /// Pulled out of `body` deliberately: inlined, this call's fifteen
    /// arguments (half of them closures) push the SwiftUI result-builder past
    /// what the type-checker will solve in reasonable time.
    private func card(for workoutExercise: WorkoutExercise) -> some View {
        ExerciseCardView(
            workoutExercise: workoutExercise,
            allExercises: sortedExercises,
            ghosts: ghosts(for: workoutExercise),
            currentRestSeconds: restDuration(for: workoutExercise),
            bodyweightKg: workout.bodyweightKg,
            useBodyweightInVolume: currentProfile()?.useBodyweightInVolume ?? true,
            onSetCompleted: handleCompleted,
            onSetUncompleted: handleUncompleted,
            onPlanChanged: {
                try? modelContext.save()
                refreshActivity()
            },
            onDropAdded: handleDropAdded,
            onGroupWith: { partner in group(workoutExercise, with: partner) },
            onUngroup: { ungroup(workoutExercise) },
            onRemove: { remove(workoutExercise) },
            onShowDetail: { detailExercise = workoutExercise.exercise },
            onSetRestConfig: { seconds, saveAsDefault in
                applyRestConfig(workoutExercise, seconds: seconds, saveAsDefault: saveAsDefault)
            }
        )
    }

    // MARK: - Header

    /// Item 10: while resting there were two live clocks on screen — this
    /// one counting up and the rest bar counting down — drawn in similar
    /// weight with nothing saying which was which. A glance couldn't answer
    /// "am I resting or working," which is the only question this screen has
    /// to answer instantly.
    ///
    /// The session clock now sits in a labelled pill and steps back while
    /// rest is running, leaving the countdown as the single loud number.
    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                TimelineView(.periodic(from: workout.startedAt, by: 1)) { context in
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "stopwatch")
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
                        Text(formattedDuration(context.date.timeIntervalSince(workout.startedAt)))
                            .dsFont(
                                isResting ? DS.TypeScale.caption : DS.TypeScale.heading,
                                relativeTo: isResting ? .subheadline : .title2,
                                weight: .semibold,
                                design: .rounded
                            )
                            .monospacedDigit()
                    }
                    .foregroundStyle(isResting ? .secondary : .primary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, isResting ? 5 : DS.Space.xxs + 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .accessibilityLabel("Session time")
                }
                .animation(.snappy(duration: 0.25), value: isResting)

                Spacer(minLength: 0)
            }

            HStack(spacing: DS.Space.sm) {
                Label(Weight.formatTotal(kg: totalVolume, in: unit), systemImage: "scalemass")
                Label("\(totalSets) sets", systemImage: "checkmark.circle")
            }
            .dsFont(DS.TypeScale.caption, relativeTo: .caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var isResting: Bool {
        workout.restEndsAt != nil && workout.restingExerciseID != nil
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

    private func handleCompleted(_ workoutExercise: WorkoutExercise, _ setLog: SetLog) {
        recalculateCachedStats()
        recordForDetection(workoutExercise)

        // PRD §10.2 "Auto-start rest timer" — off means sets simply don't
        // start a rest period (see the `UserProfile.autoStartRestTimer` doc
        // comment for why there's no manual-start fallback in V1).
        let autoStartEnabled = currentProfile()?.autoStartRestTimer ?? true
        if autoStartEnabled, WorkoutEngine.shouldStartRest(after: setLog, in: workoutExercise, allExercises: sortedExercises) {
            startRest(for: workoutExercise, setLog: setLog)
        }
        try? modelContext.save()
        refreshActivity()
    }

    /// M6 §9.2: the end instant is computed once, here, and written to the
    /// `Workout` — every other consumer (bar, notification, island) reads it
    /// rather than re-deriving a duration of its own.
    private func startRest(for workoutExercise: WorkoutExercise, setLog: SetLog) {
        let now = Date()
        let duration = max(restDuration(for: workoutExercise), 15)
        setLog.restStartedAt = now
        workout.restingExerciseID = workoutExercise.id
        workout.restStartedAt = now
        workout.restEndsAt = now.addingTimeInterval(TimeInterval(duration))
        restStartedWhileBackgrounded = false
        scheduleRestNotification(for: workoutExercise)
    }

    /// §7.5 −15s/+15s. Floors at 15s from now so "−15s" on a nearly-expired
    /// timer can't push the end instant into the past, which would fire the
    /// completion path mid-gesture.
    private func adjustRest(by delta: Int, for workoutExercise: WorkoutExercise) {
        guard let current = workout.restEndsAt else { return }
        workout.restEndsAt = max(current.addingTimeInterval(TimeInterval(delta)), Date().addingTimeInterval(15))
        rescheduleRestNotification(for: workoutExercise)
    }

    /// §7.5, item 9: the in-app control is a slider, so it sets the remaining
    /// time outright. Zero is honoured — dragging the thumb to the left end
    /// is a legitimate way to end rest, and clamping it to a 15s floor the
    /// way `adjustRest` does would make the slider lie about its own range.
    private func setRest(remainingSeconds: Int, for workoutExercise: WorkoutExercise) {
        guard workout.restEndsAt != nil else { return }
        if remainingSeconds <= 0 {
            clearRest()
            return
        }
        workout.restEndsAt = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        rescheduleRestNotification(for: workoutExercise)
    }

    private func handleUncompleted(_ workoutExercise: WorkoutExercise, _ setLog: SetLog) {
        recalculateCachedStats()
        if workout.restingExerciseID == workoutExercise.id {
            clearRest()
        }
        try? modelContext.save()
        refreshActivity()
    }

    /// §7.9: a drop was just added under a set on this exercise — the chain
    /// isn't over, so any rest already ticking for it is stale. Unlike the
    /// superset round check, this fires regardless of round state: an open
    /// drop chain always wins (`shouldStartRest`'s drop gate is the same rule
    /// at tick time; this is its mirror at add-time, for the case where the
    /// tick already started a timer before the drop existed).
    private func handleDropAdded(_ workoutExercise: WorkoutExercise) {
        if workout.restingExerciseID == workoutExercise.id {
            clearRest()
        }
        try? modelContext.save()
        refreshActivity()
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
        workout.restingExerciseID = nil
        workout.restStartedAt = nil
        workout.restEndsAt = nil
        restStartedWhileBackgrounded = false
        pendingRestContent = nil
        RestNotificationScheduler.cancelPending()
    }

    private func checkRestExpiry() {
        guard let restEndsAt = workout.restEndsAt, Date() >= restEndsAt else { return }
        let elapsed = Int(restEndsAt.timeIntervalSince(workout.restStartedAt ?? restEndsAt))

        let completedWhileBackgrounded = restStartedWhileBackgrounded
        let content = pendingRestContent ?? .init(durationSeconds: elapsed, nextLine: nil)
        clearRest()
        refreshActivity()

        if completedWhileBackgrounded {
            // The system notification (if permission was already granted)
            // already alerted the user while the app was away — this
            // foreground moment is instead the one PRD-specified trigger for
            // asking permission, so future rests can notify too.
            RestNotificationScheduler.handleBackgroundedCompletion {
                isShowingNotificationPrimer = true
            }
        } else {
            // The one moment in a workout where the app speaks first, so
            // it gets the only ascending pattern in the vocabulary.
            Haptics.play(.restComplete)
            if currentProfile()?.restTimerSoundEnabled ?? true {
                AudioServicesPlaySystemSound(1005) // PRD §10.2 "Rest timer sound"
            }
            presentRestCompleteBanner(content)
        }
    }

    /// Build 5 item G: resigns whichever field is focused, rather than
    /// clearing a stored `@FocusState`. A `TextField` inside any set row on
    /// any exercise card could be the one holding the keyboard up, and
    /// routing that focus state up through every card and row just to give
    /// this one toolbar button something to clear would be a lot of plumbing
    /// for a button that only ever needs to say "whoever you are, give up
    /// first responder."
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Rest notification scheduling (§7.5)

    private func scheduleRestNotification(for workoutExercise: WorkoutExercise) {
        guard let fireDate = workout.restEndsAt else { return }
        let duration = Int(fireDate.timeIntervalSince(workout.restStartedAt ?? Date()))
        let next = WorkoutEngine.nextSet(after: workoutExercise, allExercises: sortedExercises, ghostsProvider: ghosts(for:))
        let nextLine = next.map { "\($0.exerciseName) · \($0.positionLabel) · \(Weight.format(kg: $0.weightKg, in: unit, includeUnit: true)) × \($0.reps)" }
        let content = RestNotificationScheduler.Content(durationSeconds: duration, nextLine: nextLine)
        pendingRestContent = content
        RestNotificationScheduler.schedule(fireAt: fireDate, content: content)
    }

    /// PRD §7.5: adjusting the timer (−15s/+15s) or changing the exercise's
    /// rest config mid-rest both change the fire time, so the stale
    /// notification is cancelled (inside `schedule`) and a fresh one takes
    /// its place — not just cancelled outright.
    private func rescheduleRestNotification(for workoutExercise: WorkoutExercise) {
        guard workout.restingExerciseID == workoutExercise.id else { return }
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
        // Build 5 item D (iii): the whole feature is a soft nudge — PRD
        // §7.8.1 — and one report called it outright annoying, so it ships
        // with an off switch. Gating the entire function, not just the
        // alert, means flipping it off mid-workout also stops history from
        // accumulating: a pair that was pending when the toggle flipped
        // can't resurface if it's flipped back on later in the same session.
        guard currentProfile()?.supersetSuggestionsEnabled ?? true else { return }

        recentHistory.append(workoutExercise.id)
        if recentHistory.count > 6 { recentHistory.removeFirst() }

        guard workoutExercise.supersetGroup == nil else { return }
        guard let previousID = recentHistory.dropLast().last(where: { $0 != workoutExercise.id }) else { return }
        guard let previous = sortedExercises.first(where: { $0.id == previousID }),
              previous.supersetGroup == nil else { return }

        let key = PairKey(workoutExercise.id, previous.id)
        guard !declinedPairs.contains(key) else { return }
        guard hasIncompleteExpectedSets(previous) else { return }
        // Build 5 item D (ii): a superset has *no rest* between A and B by
        // definition — so alternating exercises only looks like a candidate
        // if the previous one's last tick is still within its own rest
        // window. Once a full rest has passed, a trailing un-ticked row on
        // the exercise you left isn't evidence of a superset, it's evidence
        // you moved on for the day.
        guard isWithinRestWindow(of: previous) else { return }

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

    /// Build 5 item D (i): "left mid-way" used to compare a *count* of
    /// completed sets against history-only `expected`, so trimming a plan
    /// below what history remembered nagged forever, and an out-of-order tick
    /// (row 0 and row 2 done, row 1 open) read as "2 of 3 done" — true for
    /// the rest of the session even after row 1 was filled in. `planned` now
    /// comes from the same "how many rows does this card have" arithmetic
    /// the pointer and the card itself use (`WorkoutEngine.rowCount`,
    /// extracted for item E so the two can't diverge), and progress is read
    /// off the highest completed row's *position*, not a count — so ticking
    /// the actual last row always ends detection, regardless of what order
    /// the rows were filled in.
    private func hasIncompleteExpectedSets(_ workoutExercise: WorkoutExercise) -> Bool {
        let planned = WorkoutEngine.rowCount(for: workoutExercise, ghostCount: ghosts(for: workoutExercise).count)
        // Top-level sets only (§7.9) — a drop chain is a continuation of a
        // set, not a row of its own.
        let topLevelSets = (workoutExercise.sets ?? []).filter { $0.parentSetID == nil }
        let completed = topLevelSets.filter(\.isCompleted)
        guard let highest = completed.map(\.orderIndex).max() else { return false }
        return highest + 1 < planned
    }

    /// Build 5 item D (ii)'s timing gate. `restDuration(for:)` is the same
    /// override → exercise-default → profile-default chain the rest timer
    /// itself resolves against (§7.5), so this reads the identical number
    /// the user would have seen counting down — it always resolves to a
    /// positive value rather than failing, so the 90s floor only matters if
    /// that chain is ever loosened to return something falsy.
    private func isWithinRestWindow(of workoutExercise: WorkoutExercise) -> Bool {
        let lastCompletedAt = (workoutExercise.sets ?? [])
            .filter { $0.parentSetID == nil && $0.isCompleted }
            .compactMap(\.completedAt)
            .max()
        guard let lastCompletedAt else { return false }
        let resolvedRestSeconds = restDuration(for: workoutExercise)
        let restWindow = TimeInterval(resolvedRestSeconds > 0 ? resolvedRestSeconds : 90)
        return Date().timeIntervalSince(lastCompletedAt) <= restWindow
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
        if workout.restingExerciseID == workoutExercise.id { clearRest() }
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
        } else if hasDivergedFromTemplate {
            showingDivergencePrompt = true
        } else {
            finish()
        }
    }

    /// Item 11: did this session end up doing different *exercises* than the
    /// template called for?
    ///
    /// Compares the exercise list only — sets, reps and weights are expected
    /// to differ every session and are the whole point of logging. Swapping,
    /// adding or dropping a movement is the thing that means "this is a
    /// different day now," and it is the only thing worth asking about.
    private var hasDivergedFromTemplate: Bool {
        guard let routine = workout.routine else { return false }
        let planned = (routine.exercises ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.exercise?.id }
        let performed = sortedExercises.compactMap { $0.exercise?.id }
        return planned != performed
    }

    /// "Save as new workout": the session's exercise list becomes its own
    /// entry in the library, alongside the original. Deliberately a *copy*
    /// rather than an edit — the template you diverged from is often still
    /// the one you want next week, and silently rewriting it would lose a
    /// plan the user never asked to change.
    private func saveAsNewWorkout() {
        let source = workout.routine
        let copy = Routine(
            name: "\(workout.title) (new)",
            notes: source?.notes,
            folder: source?.folder,
            orderIndex: (try? modelContext.fetch(FetchDescriptor<Routine>()))?.count ?? 0
        )
        copy.trackAsProgress = source?.trackAsProgress ?? true
        copy.updateValuesOnFinish = source?.updateValuesOnFinish ?? true
        modelContext.insert(copy)

        for (index, workoutExercise) in sortedExercises.enumerated() {
            guard let exercise = workoutExercise.exercise else { continue }
            let routineExercise = RoutineExercise(
                orderIndex: index,
                exercise: exercise,
                supersetGroup: workoutExercise.supersetGroup
            )
            routineExercise.restSecondsOverride = workoutExercise.restSecondsUsed
            modelContext.insert(routineExercise)
            routineExercise.routine = copy

            // Seed the new plan from what was actually performed — top-level
            // sets only, since a drop chain is a decision made in the moment
            // rather than a target to aim at next time (§7.9).
            let performed = (workoutExercise.sets ?? [])
                .filter { $0.isCompleted && $0.parentSetID == nil }
                .sorted { $0.orderIndex < $1.orderIndex }
            for (position, setLog) in performed.enumerated() {
                let template = RoutineSetTemplate(
                    orderIndex: position,
                    targetWeightKg: setLog.addedWeightKg,
                    targetReps: setLog.reps,
                    setType: .normal
                )
                modelContext.insert(template)
                template.routineExercise = routineExercise
            }
        }
        try? modelContext.save()
    }

    private func finish() {
        // A pending rest notification would otherwise fire for a workout
        // that's already over, pointing at a "next set" nobody's doing.
        clearRest()
        // §7 row 28: ended immediately, no FINISHED presentation.
        LiveActivityController.shared.end()
        // Home-screen widgets show streak, this-week count and "last
        // performed" — all of which just changed. Without this they'd sit
        // stale until the hourly backstop.
        WidgetCenter.shared.reloadAllTimelines()
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
        // PRD §10.2 "Write workout sessions." Detached from the save above on
        // purpose: the workout is already durable locally, so a Health write
        // that's slow, unauthorized, or failing must never delay the summary
        // screen or surface an error (§9.7 silent fallback).
        Task { await HealthKitManager.writeWorkout(workout) }
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
            //
            // Only when the exercise was actually performed. Zero completed
            // sets means "skipped today," not "this exercise has no sets" —
            // trimming there deleted *every* target, so skipping one movement
            // once permanently wiped its plan (and silently gutted an
            // imported template). The exercise keeps its targets untouched.
            if !completed.isEmpty, templates.count > completed.count {
                for extra in templates[completed.count...] {
                    modelContext.delete(extra)
                }
            }
        }
    }
}
