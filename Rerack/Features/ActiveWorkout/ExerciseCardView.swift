import SwiftUI
import SwiftData

/// PRD §7.1/§7.2/§7.4. Row count = `max(ghosts + manually-added rows,
/// completed sets, 1)` — ghost rows past the completed count are pure view
/// state (§7.3) and never touch the database until ticked or edited.
struct ExerciseCardView: View {
    @Bindable var workoutExercise: WorkoutExercise
    let allExercises: [WorkoutExercise]
    let ghosts: [GhostSet]

    let onSetCompleted: (WorkoutExercise, SetLog) -> Void
    let onSetUncompleted: (WorkoutExercise, SetLog) -> Void
    let onGroupWith: (WorkoutExercise) -> Void
    let onUngroup: () -> Void
    let onRemove: () -> Void
    let onShowDetail: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var extraRows = 0
    @State private var showingGroupPicker = false

    private var completedSets: [SetLog] {
        (workoutExercise.sets ?? []).filter(\.isCompleted).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var rowCount: Int {
        max(ghosts.count + extraRows, completedSets.count, 1)
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
                SetRowView(
                    orderIndex: index,
                    existingSet: index < completedSets.count ? completedSets[index] : nil,
                    ghost: GhostSetResolver.ghostSet(at: index, in: ghosts),
                    onComplete: { weight, reps in complete(index: index, weight: weight, reps: reps) },
                    onUncomplete: { uncomplete(index: index) },
                    onDeleteExisting: { deleteExisting(index: index) }
                )
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
    }

    private func complete(index: Int, weight: Double, reps: Int) {
        let setLog: SetLog
        if index < completedSets.count {
            setLog = completedSets[index]
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
        onSetCompleted(workoutExercise, setLog)
    }

    private func uncomplete(index: Int) {
        guard index < completedSets.count else { return }
        let setLog = completedSets[index]
        setLog.isCompleted = false
        setLog.completedAt = nil
        setLog.restStartedAt = nil
        onSetUncompleted(workoutExercise, setLog)
    }

    private func deleteExisting(index: Int) {
        guard index < completedSets.count else { return }
        let setLog = completedSets[index]
        modelContext.delete(setLog)
        let remaining = (workoutExercise.sets ?? []).filter(\.isCompleted).sorted { $0.orderIndex < $1.orderIndex }
        for (i, log) in remaining.enumerated() {
            log.orderIndex = i
        }
    }
}
