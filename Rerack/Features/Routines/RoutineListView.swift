import SwiftUI
import SwiftData

/// PRD §9.3. Grouped by folder when folders exist; a flat "No Folder" group
/// otherwise. Meant to be embedded directly inside the `List` in
/// `WorkoutTabView` — its body is `Section`s, not a standalone scroll view.
struct RoutineListView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

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
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("No workouts yet")
                    .dsFont(DS.TypeScale.body, relativeTo: .subheadline, weight: .medium)
                Text("Build one above, or start from a template.")
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, DS.Space.xxs)
        } else {
            ForEach(grouped, id: \.folderName) { group in
                Section(group.folderName) {
                    ForEach(group.routines) { routine in
                        RoutineCard(
                            routine: routine,
                            isStartDisabled: coordinator.liveWorkout != nil,
                            onStart: { start(routine) },
                            onEdit: { editingRoutine = routine },
                            onDuplicate: { duplicate(routine) },
                            onDelete: { modelContext.delete(routine) }
                        )
                    }
                    // Drag to reorder within a split, so adding a Wednesday
                    // legs day doesn't strand it at the bottom. Reordering is
                    // scoped to the folder: `orderIndex` is global, so moving
                    // within one group has to renumber only that group's rows
                    // or it would silently reshuffle every other split.
                    .onMove { offsets, destination in
                        move(in: group.routines, from: offsets, to: destination)
                    }
                }
            }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }

    private func move(in group: [Routine], from offsets: IndexSet, to destination: Int) {
        var reordered = group
        reordered.move(fromOffsets: offsets, toOffset: destination)
        // Renumber using only the indices this group already occupied, so the
        // group keeps its position relative to every other folder.
        let slots = group.map(\.orderIndex).sorted()
        for (slot, routine) in zip(slots, reordered) {
            routine.orderIndex = slot
        }
        try? modelContext.save()
    }

    /// PRD §7.7 / §9.3: creates the Workout + WorkoutExercise shells and
    /// hands off to the coordinator. Guarded against starting with nothing
    /// to do or while another workout is already live (§6).
    private func start(_ routine: Routine) {
        guard coordinator.liveWorkout == nil else { return }
        guard !(routine.exercises ?? []).isEmpty else { return }
        let workout = WorkoutStarter.start(routine: routine, context: modelContext)
        routine.lastPerformedAt = Date()
        try? modelContext.save()
        coordinator.present(workout)
    }

    /// PRD §9.3 long-press menu includes Duplicate. Deep-copies the
    /// exercise/set-template structure but not history (a duplicate is a
    /// fresh plan, not a fresh log).
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
