import SwiftUI
import SwiftData

/// PRD §9.3. Grouped by folder when folders exist; a flat "No Folder" group
/// otherwise. Meant to be embedded directly inside the `List` in
/// `WorkoutTabView` — its body is `Section`s, not a standalone scroll view.
struct RoutineListView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Environment(\.modelContext) private var modelContext

    @State private var editingRoutine: Routine?

    private var grouped: [(folderName: String, routines: [Routine])] {
        let groups = Dictionary(grouping: routines) { $0.folder?.name ?? "" }
        let orderedKeys = groups.keys.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return orderedKeys.map { key in
            (key.isEmpty ? "No Folder" : key, groups[key]!.sorted { $0.orderIndex < $1.orderIndex })
        }
    }

    var body: some View {
        if routines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No routines yet")
                    .font(.subheadline.weight(.medium))
                Text("Tap \"+ New Routine\" below to build your first one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            ForEach(grouped, id: \.folderName) { group in
                Section(group.folderName) {
                    ForEach(group.routines) { routine in
                        RoutineCard(routine: routine)
                            .contentShape(Rectangle())
                            .onTapGesture { editingRoutine = routine }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(routine)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    duplicate(routine)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }

    /// PRD §9.3 long-press menu includes Duplicate — implemented here as a
    /// swipe action since the routine card doesn't have a long-press menu
    /// of its own yet. Deep-copies the exercise/set-template structure but
    /// not history (a duplicate is a fresh plan, not a fresh log).
    private func duplicate(_ routine: Routine) {
        let copy = Routine(
            name: "\(routine.name) copy",
            notes: routine.notes,
            folder: routine.folder,
            orderIndex: routines.count
        )
        copy.trackAsProgress = routine.trackAsProgress
        copy.updateValuesOnFinish = routine.updateValuesOnFinish
        modelContext.insert(copy)

        let sourceExercises = (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        for sourceExercise in sourceExercises {
            guard let exercise = sourceExercise.exercise else { continue }
            let exerciseCopy = RoutineExercise(
                orderIndex: sourceExercise.orderIndex,
                exercise: exercise,
                supersetGroup: sourceExercise.supersetGroup
            )
            exerciseCopy.intraSupersetRestSeconds = sourceExercise.intraSupersetRestSeconds
            exerciseCopy.restSecondsOverride = sourceExercise.restSecondsOverride
            exerciseCopy.notes = sourceExercise.notes
            modelContext.insert(exerciseCopy)
            exerciseCopy.routine = copy

            let sourceTemplates = (sourceExercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }
            for sourceTemplate in sourceTemplates {
                let templateCopy = RoutineSetTemplate(
                    orderIndex: sourceTemplate.orderIndex,
                    targetWeightKg: sourceTemplate.targetWeightKg,
                    targetReps: sourceTemplate.targetReps,
                    setType: sourceTemplate.setType
                )
                modelContext.insert(templateCopy)
                templateCopy.routineExercise = exerciseCopy
            }
        }

        try? modelContext.save()
    }
}
