import SwiftUI
import SwiftData

/// §7.9: a drop row the user has swiped "+ Drop" onto but not yet ticked.
/// Pure view state, same invariant as a ghost set (§7.3) — it never touches
/// the database until completed. `parentSetID` is always the *root* set of
/// the chain (the completed normal set), even when added from an existing
/// drop further down — PRD's data model is one parent with drops chained
/// off it, not a nested tree, so every drop in a chain shares one ID to
/// filter by.
private struct PendingDrop: Identifiable {
    let id = UUID()
    let parentSetID: UUID
    let prefillWeightKg: Double
}

/// PRD §7.1/§7.2/§7.4/§7.9. Row count = `max(ghosts + manually-added rows,
/// completed sets, 1)` — ghost rows past the completed count are pure view
/// state (§7.3) and never touch the database until ticked or edited. Drop
/// chains render underneath their parent's row and are counted separately
/// (§7.9) so they never shift the numbering ghosts are matched against.
struct ExerciseCardView: View {
    @Bindable var workoutExercise: WorkoutExercise
    let allExercises: [WorkoutExercise]
    let ghosts: [GhostSet]
    /// The rest duration currently in effect for this exercise (§7.5
    /// hierarchy, resolved by the caller) — seeds the rest picker's wheel so
    /// it opens on "what would apply right now," not some fixed default.
    let currentRestSeconds: Int

    /// `Bool` is `hasPendingDrop` (§7.9) — whether the completed set still
    /// has an uncommitted drop row waiting under it, so the caller can feed
    /// it straight into `WorkoutEngine.shouldStartRest`.
    let onSetCompleted: (WorkoutExercise, SetLog, _ hasPendingDrop: Bool) -> Void
    let onSetUncompleted: (WorkoutExercise, SetLog) -> Void
    /// §7.9: a drop was just added under an already-resting set — the caller
    /// cancels any rest timer running for this exercise, since the chain it
    /// belongs to is no longer "over."
    let onDropAdded: (WorkoutExercise) -> Void
    let onGroupWith: (WorkoutExercise) -> Void
    let onUngroup: () -> Void
    let onRemove: () -> Void
    let onShowDetail: () -> Void
    /// §7.4/§7.5: sets the per-exercise-in-workout override, or (if the sheet's
    /// "save as default" toggle is on) the exercise's own default instead.
    let onSetRestConfig: (_ seconds: Int, _ saveAsDefault: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var extraRows = 0
    @State private var showingGroupPicker = false
    @State private var showingRestPicker = false
    @State private var pendingDrops: [PendingDrop] = []

    /// Every top-level set row that exists in the store, completed or not —
    /// drops are rendered as children of these (§7.9), so they stay out of
    /// the numbering ghosts are matched against.
    ///
    /// Un-ticking a set (§7.2) leaves the row in place with
    /// `isCompleted == false`. Everything below must therefore address rows
    /// by **`orderIndex`, never by position in a completed-only array** —
    /// indexing a filtered list was the source of two real bugs: re-ticking
    /// an un-ticked set inserted a *duplicate* `SetLog` and orphaned the
    /// original, and un-ticking set 1 of 3 made set 2's values render in set
    /// 1's slot.
    private var topLevelSets: [SetLog] {
        (workoutExercise.sets ?? []).filter { $0.parentSetID == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func setLog(at index: Int) -> SetLog? {
        topLevelSets.first { $0.orderIndex == index }
    }

    /// Only completed rows count toward how many rows must exist.
    private var completedSetCount: Int {
        topLevelSets.filter(\.isCompleted).count
    }

    private var rowCount: Int {
        max(ghosts.count + extraRows, completedSetCount, 1)
    }

    private var supersetLabel: String? {
        SupersetGrouping.label(for: workoutExercise, among: allExercises)
    }

    private var groupCandidates: [WorkoutExercise] {
        allExercises.filter { $0.id != workoutExercise.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let supersetLabel {
                    Text(supersetLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Button(action: onShowDetail) {
                    Text(workoutExercise.exercise?.name ?? "Exercise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button {
                        showingRestPicker = true
                    } label: {
                        Label("Set Rest Timer", systemImage: "timer")
                    }
                    Button {
                        showingGroupPicker = true
                    } label: {
                        Label("Add to Superset", systemImage: "link")
                    }
                    if workoutExercise.supersetGroup != nil {
                        Button(action: onUngroup) {
                            Label("Remove from Superset", systemImage: "link.badge.minus")
                        }
                    }
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
            }

            ForEach(0..<rowCount, id: \.self) { index in
                // Only a *completed* row is passed as `existingSet` — an
                // un-ticked one reverts to its ghost, per §7.2/§7.3.
                let topSet = setLog(at: index).flatMap { $0.isCompleted ? $0 : nil }
                SetRowView(
                    orderIndex: index,
                    existingSet: topSet,
                    ghost: GhostSetResolver.ghostSet(at: index, in: ghosts),
                    onComplete: { weight, reps in complete(index: index, weight: weight, reps: reps) },
                    onUncomplete: { uncomplete(index: index) },
                    onDeleteExisting: { deleteExisting(index: index) },
                    onAddDrop: topSet.map { parent in { addDrop(from: parent) } }
                )
                if let topSet {
                    dropChainRows(under: topSet)
                }
            }

            Button {
                extraRows += 1
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingGroupPicker) {
            GroupWithPickerSheet(
                candidates: groupCandidates,
                nameProvider: { $0.exercise?.name ?? "Exercise" },
                onPick: onGroupWith
            )
        }
        .sheet(isPresented: $showingRestPicker) {
            RestDurationPickerSheet(
                title: "Rest Timer",
                saveAsDefaultLabel: "Save as default for \(workoutExercise.exercise?.name ?? "this exercise")",
                initialSeconds: currentRestSeconds,
                onSave: onSetRestConfig
            )
        }
    }

    // MARK: - Drop chains (§7.9)

    /// Renders a parent's committed drops, then any still-pending (unticked)
    /// ones underneath — same top-to-bottom order they were added in.
    @ViewBuilder
    private func dropChainRows(under parent: SetLog) -> some View {
        let committed = (workoutExercise.sets ?? [])
            .filter { $0.parentSetID == parent.id }
            .sorted { $0.orderIndex < $1.orderIndex }
        ForEach(committed) { drop in
            SetRowView(
                orderIndex: 0,
                existingSet: drop,
                ghost: nil,
                isDrop: true,
                onComplete: { _, _ in }, // already committed; only un-tick applies
                onUncomplete: { uncompleteDrop(drop) },
                onDeleteExisting: { deleteDrop(drop) },
                onAddDrop: drop.isCompleted ? { addDrop(from: drop) } : nil
            )
        }
        ForEach(pendingDrops.filter { $0.parentSetID == parent.id }) { pending in
            SetRowView(
                orderIndex: 0,
                existingSet: nil,
                ghost: nil,
                isDrop: true,
                dropPrefillWeightKg: pending.prefillWeightKg,
                onComplete: { weight, reps in completePendingDrop(pending, weight: weight, reps: reps) },
                onUncomplete: {},
                onDeleteExisting: { pendingDrops.removeAll { $0.id == pending.id } }
            )
        }
    }

    /// PRD §7.9/§15: only reachable from a completed row (`SetRowView`
    /// withholds `onAddDrop` otherwise), so the parent-must-be-ticked edge
    /// case is enforced by construction rather than checked here again.
    /// `parentSetID` is always the chain's root — see `PendingDrop`.
    private func addDrop(from setLog: SetLog) {
        let rootID = setLog.parentSetID ?? setLog.id
        let prefill = DropSetMath.prefillWeightKg(fromParent: setLog.addedWeightKg)
        pendingDrops.append(PendingDrop(parentSetID: rootID, prefillWeightKg: prefill))
        // The chain this belongs to is no longer "over" — cancel any rest
        // already running for this exercise (§7.5/§7.9).
        onDropAdded(workoutExercise)
    }

    private func completePendingDrop(_ pending: PendingDrop, weight: Double, reps: Int) {
        let setLog = SetLog(orderIndex: (workoutExercise.sets ?? []).count, setType: .drop, addedWeightKg: weight, reps: reps)
        setLog.parentSetID = pending.parentSetID
        // TODO M9 (§13.1): see the matching TODO in `complete(index:)`.
        setLog.effectiveLoadKg = weight
        setLog.isCompleted = true
        setLog.completedAt = Date()
        modelContext.insert(setLog)
        setLog.workoutExercise = workoutExercise
        pendingDrops.removeAll { $0.id == pending.id }
        let hasPendingDrop = pendingDrops.contains { $0.parentSetID == pending.parentSetID }
        onSetCompleted(workoutExercise, setLog, hasPendingDrop)
    }

    private func uncompleteDrop(_ drop: SetLog) {
        drop.isCompleted = false
        drop.completedAt = nil
        drop.restStartedAt = nil
        onSetUncompleted(workoutExercise, drop)
    }

    private func deleteDrop(_ drop: SetLog) {
        modelContext.delete(drop)
    }

    private func complete(index: Int, weight: Double, reps: Int) {
        let setLog: SetLog
        // Reuse any row already at this index — including one that was
        // un-ticked — rather than inserting a second row for the same set.
        if let existing = self.setLog(at: index) {
            setLog = existing
        } else {
            setLog = SetLog(orderIndex: index)
            modelContext.insert(setLog)
            setLog.workoutExercise = workoutExercise
        }
        setLog.addedWeightKg = weight
        setLog.reps = reps
        // TODO M9 (§13.1): effectiveLoadKg should fold in bodyweight ×
        // factor for bodyweight/weighted/assisted exercises once Health
        // integration exists. External-load exercises are already correct.
        setLog.effectiveLoadKg = weight
        setLog.isCompleted = true
        setLog.completedAt = Date()
        // §7.9: this set's own chain is open if a drop is already pending
        // under it (e.g. "+ Drop" was tapped before the tick landed).
        let hasPendingDrop = pendingDrops.contains { $0.parentSetID == setLog.id }
        onSetCompleted(workoutExercise, setLog, hasPendingDrop)
    }

    private func uncomplete(index: Int) {
        guard let setLog = self.setLog(at: index) else { return }
        setLog.isCompleted = false
        setLog.completedAt = nil
        setLog.restStartedAt = nil
        onSetUncompleted(workoutExercise, setLog)
    }

    private func deleteExisting(index: Int) {
        guard let setLog = self.setLog(at: index) else { return }
        // §7.9: a parent's drops are part of its row, not independent —
        // deleting the parent takes the whole chain with it rather than
        // leaving drops pointing at a `parentSetID` that no longer exists.
        for drop in (workoutExercise.sets ?? []).filter({ $0.parentSetID == setLog.id }) {
            modelContext.delete(drop)
        }
        modelContext.delete(setLog)
        // Renumber every remaining top-level row, completed or not — an
        // un-ticked row still occupies its slot, so skipping it here would
        // leave a gap that `setLog(at:)` could never match again.
        for (i, log) in topLevelSets.enumerated() where log.orderIndex != i {
            log.orderIndex = i
        }
    }
}
