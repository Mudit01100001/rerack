import SwiftUI
import SwiftData

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

    /// §13.1: the workout's bodyweight snapshot and the user's "use bodyweight
    /// in volume maths" preference, resolved once by the caller rather than
    /// re-fetched per set tick.
    let bodyweightKg: Double?
    let useBodyweightInVolume: Bool

    let onSetCompleted: (WorkoutExercise, SetLog) -> Void
    let onSetUncompleted: (WorkoutExercise, SetLog) -> Void
    /// M6 §7 rows 20–22: any change to the *plan* — add set, delete set,
    /// delete a drop — moves the pointer without completing anything, and the
    /// Live Activity must be told or it renders a set that no longer exists.
    let onPlanChanged: () -> Void
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
    @State private var showingGroupPicker = false
    @State private var showingRestPicker = false
    @State private var showingPlateCalculator = false

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

    /// M6 §9.1: `plannedSetCount` is the persisted replacement for what used
    /// to be a `@State extraRows` counter. Unset means "however many ghosts
    /// resolve," so a routine-driven exercise needs nothing written until
    /// `+ Add Set` is actually tapped.
    private var rowCount: Int {
        max(workoutExercise.plannedSetCount ?? ghosts.count, completedSetCount, 1)
    }

    private var supersetLabel: String? {
        SupersetGrouping.label(for: workoutExercise, among: allExercises)
    }

    private var groupCandidates: [WorkoutExercise] {
        allExercises.filter { $0.id != workoutExercise.id }
    }

    // MARK: - Card header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                if let supersetLabel {
                    Text(supersetLabel)
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                }
                Button(action: onShowDetail) {
                    Text(workoutExercise.exercise?.name ?? "Exercise")
                        .dsFont(DS.TypeScale.heading, relativeTo: .headline, weight: .semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Spacer(minLength: DS.Space.xxs)
                menu
            }

            // Rest config belongs to this exercise, so it sits in the card's
            // header. Rendered as a tinted, chevroned chip rather than grey
            // caption text: previously it read as a static label and nobody
            // could tell it was tappable.
            Button {
                showingRestPicker = true
            } label: {
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "timer")
                    Text(RestNotificationScheduler.formattedClock(currentRestSeconds))
                    Image(systemName: "chevron.down")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
                }
                .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .medium)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, DS.Space.xs)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest timer, \(RestNotificationScheduler.formattedClock(currentRestSeconds)). Tap to change.")
        }
        .padding(.horizontal, DS.Space.xxs)
    }

    /// Column headers replace the old inline "12.5 × 10" ghost text that sat
    /// unlabelled beside each input — a bare pair of numbers next to a field
    /// you're typing into reads as a second input, not as last session's
    /// figures. Naming the columns once at the top says it for every row.
    private var columnHeaders: some View {
        HStack(spacing: DS.Space.xs) {
            Text("SET")
                .frame(width: 26, alignment: .leading)
            Text("PREVIOUS")
                .frame(width: 66, alignment: .leading)
            Text("KG")
                .frame(width: 58, alignment: .center)
            Text("REPS")
                .frame(width: 48, alignment: .center)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .frame(width: 30)
        }
        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
        .tracking(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Space.sm)
        .padding(.top, DS.Space.xs + 2)
        .padding(.bottom, DS.Space.xxs)
        .accessibilityHidden(true) // each row already reads its own values
    }

    private var menu: some View {
        Menu {
            Button {
                showingRestPicker = true
            } label: {
                Label("Set Rest Timer", systemImage: "timer")
            }
            // Offered on every exercise rather than only the ones we can
            // prove use a bar: equipment metadata is a hand-written guess
            // (§23.1), and hiding the calculator on a mislabelled row is
            // worse than showing it on one that doesn't need it.
            Button {
                showingPlateCalculator = true
            } label: {
                Label("Plate Calculator", systemImage: "circle.grid.2x2")
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
            Image(systemName: "ellipsis")
                .imageScale(.large)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Set list

    /// Alternating row tints. The set rows are dense numeric fields, and with
    /// a flat background the eye loses which weight belongs to which reps —
    /// the banding is doing real legibility work, not decoration. Drop rows
    /// inherit their parent's band so a chain reads as one block.
    private var setList: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                // Only a *completed* row is passed as `existingSet` — an
                // un-ticked one reverts to its ghost, per §7.2/§7.3.
                let topSet = setLog(at: index).flatMap { $0.isCompleted ? $0 : nil }
                let rowGhost = GhostSetResolver.ghostSet(at: index, in: ghosts)
                VStack(spacing: 0) {
                    SetRowView(
                        orderIndex: index,
                        existingSet: topSet,
                        ghost: rowGhost,
                        onComplete: { weight, reps in complete(index: index, weight: weight, reps: reps) },
                        onUncomplete: { uncomplete(index: index) },
                        onDeleteExisting: { deleteExisting(index: index) },
                        onAddDrop: topSet.map { parent in { addDrop(from: parent) } }
                    )
                    if let topSet {
                        dropChainRows(under: topSet, ghostDrops: rowGhost?.drops ?? [])
                    }
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xxs)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
            }
        }
        .padding(.bottom, DS.Space.xxs)
    }

    private var addSetButton: some View {
        Button {
            workoutExercise.plannedSetCount = rowCount + 1
            onPlanChanged()
        } label: {
            Label("Add Set", systemImage: "plus")
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    /// One exercise = one card: a header block (name, rest setting, `···`),
    /// then the set list, then `Add Set`. Grouping them this way is what makes
    /// a long workout scannable — before, every exercise ran together into one
    /// undifferentiated column of rows.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            header
            // The set list lives in its own inset container rather than
            // running edge-to-edge: it groups the rows as one block, and the
            // concentric radius keeps its curve parallel to the card's.
            VStack(spacing: 0) {
                columnHeaders
                setList
            }
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: .rect(
                    cornerRadius: DS.concentricRadius(outer: DS.Radius.large, inset: DS.Space.sm),
                    style: .continuous
                )
            )
            addSetButton
        }
        .padding(DS.Space.sm)
        .dsCard()
        .sheet(isPresented: $showingPlateCalculator) {
            PlateCalculatorSheet(
                exerciseName: workoutExercise.exercise?.name ?? "Exercise",
                equipment: workoutExercise.exercise?.equipment ?? .barbell
            )
        }
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

    /// Renders a parent's drop chain. Every row here is a real `SetLog`,
    /// ticked or not (M6 §9.3) — including the ones reproduced from last
    /// session's chain, which `materialiseGhostDrops` inserts the moment the
    /// parent is ticked. An un-ticked row still *reads* as a suggestion
    /// (grey, §7.3) because `SetRowView` styles on `isCompleted`, not on
    /// whether a row exists.
    @ViewBuilder
    private func dropChainRows(under parent: SetLog, ghostDrops: [GhostSet]) -> some View {
        let chain = drops(of: parent)
        ForEach(Array(chain.enumerated()), id: \.element.id) { position, drop in
            SetRowView(
                orderIndex: 0,
                existingSet: drop,
                ghost: position < ghostDrops.count ? ghostDrops[position] : nil,
                isDrop: true,
                onComplete: { weight, reps in completeDrop(drop, weight: weight, reps: reps) },
                onUncomplete: { uncompleteDrop(drop) },
                onDeleteExisting: { deleteDrop(drop) },
                onAddDrop: drop.isCompleted ? { addDrop(from: drop) } : nil
            )
        }
    }

    private func drops(of parent: SetLog) -> [SetLog] {
        (workoutExercise.sets ?? [])
            .filter { $0.parentSetID == parent.id }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    /// PRD §7.9/§15: only reachable from a completed row (`SetRowView`
    /// withholds `onAddDrop` otherwise), so the parent-must-be-ticked edge
    /// case is enforced by construction rather than checked here again.
    ///
    /// M6 §9.3: the row is inserted **now**, unticked, rather than held as
    /// view state until it's ticked. Three things follow — the widget process
    /// can see an open chain (so the island can render `Drop 1 of 2` and
    /// suppress rest), `WorkoutEngine` can compute `hasPendingDrop` itself
    /// instead of taking it on trust from a caller, and an un-ticked drop
    /// survives a force-quit instead of silently vanishing on relaunch, which
    /// was a real data-loss bug against Principle 4 ("never lose a set").
    ///
    /// `parentSetID` is always the chain's root — PRD's model is one parent
    /// with drops chained off it, not a nested tree, so adding a drop from an
    /// existing drop still points at the original top-level set.
    private func addDrop(from setLog: SetLog) {
        let rootID = setLog.parentSetID ?? setLog.id
        let drop = SetLog(
            orderIndex: (workoutExercise.sets ?? []).count,
            setType: .drop,
            addedWeightKg: DropSetMath.prefillWeightKg(fromParent: setLog.addedWeightKg),
            reps: 0
        )
        drop.parentSetID = rootID
        modelContext.insert(drop)
        drop.workoutExercise = workoutExercise
        // The chain this belongs to is no longer "over" — cancel any rest
        // already running for this exercise (§7.5/§7.9).
        onDropAdded(workoutExercise)
    }

    /// §13.1, snapshotted into `SetLog.effectiveLoadKg` at completion time and
    /// never recomputed afterwards.
    private func effectiveLoad(addedWeightKg: Double) -> Double {
        EffectiveLoad.kg(
            addedWeightKg: addedWeightKg,
            loadType: workoutExercise.exercise?.loadType ?? .external,
            bodyweightFactor: workoutExercise.exercise?.bodyweightFactor ?? 0,
            bodyweightKg: bodyweightKg,
            useBodyweightInVolume: useBodyweightInVolume
        )
    }

    /// Ticking a drop row that already exists in the store (M6 §9.3) — every
    /// manually-added drop takes this path.
    private func completeDrop(_ drop: SetLog, weight: Double, reps: Int) {
        drop.addedWeightKg = weight
        drop.reps = reps
        drop.effectiveLoadKg = effectiveLoad(addedWeightKg: weight)
        drop.isCompleted = true
        drop.completedAt = Date()
        onSetCompleted(workoutExercise, drop)
    }

    /// PRD §7.9 closing bullet: ticking a ghost-reproduced drop materialises
    /// it, exactly like ticking a top-level ghost row materialises that.
    /// `orderIndex` is only an insertion counter shared with top-level sets —
    /// it's never used to address a drop, only to order one chain internally.
    private func completeGhostDrop(parentSetID: UUID, weight: Double, reps: Int) {
        let drop = SetLog(orderIndex: (workoutExercise.sets ?? []).count, setType: .drop, addedWeightKg: weight, reps: reps)
        drop.parentSetID = parentSetID
        drop.effectiveLoadKg = effectiveLoad(addedWeightKg: weight)
        drop.isCompleted = true
        drop.completedAt = Date()
        modelContext.insert(drop)
        drop.workoutExercise = workoutExercise
        onSetCompleted(workoutExercise, drop)
    }

    private func uncompleteDrop(_ drop: SetLog) {
        drop.isCompleted = false
        drop.completedAt = nil
        drop.restStartedAt = nil
        onSetUncompleted(workoutExercise, drop)
    }

    private func deleteDrop(_ drop: SetLog) {
        modelContext.delete(drop)
        onPlanChanged()
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
        setLog.effectiveLoadKg = effectiveLoad(addedWeightKg: weight)
        setLog.isCompleted = true
        setLog.completedAt = Date()
        // §7.9 closing bullet: reproduce last session's drop chain as real
        // un-ticked rows the moment the parent is ticked. Materialising here
        // rather than rendering ghost rows is what lets `WorkoutEngine` see
        // the open chain (and so suppress rest) without a second "is a ghost
        // chain pending" mechanism running alongside the real one.
        materialiseGhostDrops(under: setLog, at: index)
        onSetCompleted(workoutExercise, setLog)
    }

    private func materialiseGhostDrops(under parent: SetLog, at index: Int) {
        guard drops(of: parent).isEmpty else { return }
        let ghostDrops = GhostSetResolver.ghostSet(at: index, in: ghosts)?.drops ?? []
        for (offset, ghostDrop) in ghostDrops.enumerated() {
            let drop = SetLog(
                orderIndex: (workoutExercise.sets ?? []).count + offset,
                setType: .drop,
                addedWeightKg: ghostDrop.weightKg,
                reps: ghostDrop.reps
            )
            drop.parentSetID = parent.id
            modelContext.insert(drop)
            drop.workoutExercise = workoutExercise
        }
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
        onPlanChanged()
    }
}
