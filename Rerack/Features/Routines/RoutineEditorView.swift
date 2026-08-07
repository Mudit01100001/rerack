import SwiftUI
import SwiftData

/// PRD §9.3, M2. Creates or edits a routine: name, notes, folder, the two
/// per-routine progress-tracking settings, and the ordered exercise list
/// with set templates and superset grouping.
struct RoutineEditorView: View {
    @Bindable var routine: Routine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFolderPicker = false
    @State private var showingExercisePicker = false

    private var sortedExercises: [RoutineExercise] {
        (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { routine.notes ?? "" },
            set: { routine.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private var canSave: Bool {
        !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Monday — Push", text: $routine.name)
                }

                Section("Notes") {
                    TextField("Optional", text: notesBinding, axis: .vertical)
                }

                Section {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        HStack {
                            Text("Folder").foregroundStyle(.primary)
                            Spacer()
                            Text(routine.folder?.name ?? "None")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Track as progress", isOn: $routine.trackAsProgress)
                    Toggle("Update routine values on finish", isOn: $routine.updateValuesOnFinish)
                } footer: {
                    Text("Both default on. Turning off \"Track as progress\" keeps this routine's sessions in your history and export, but out of graphs and PRs — useful for deload weeks. See PRD §9.3.")
                }

                Section("Exercises") {
                    if sortedExercises.isEmpty {
                        Text("No exercises yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                            RoutineExerciseRow(
                                routineExercise: routineExercise,
                                allExercisesInRoutine: sortedExercises,
                                canMoveUp: index > 0,
                                canMoveDown: index < sortedExercises.count - 1,
                                onRemove: { remove(routineExercise) },
                                onUngroup: { ungroup(routineExercise) },
                                onGroupWith: { partner in group(routineExercise, with: partner) },
                                onMoveUp: { moveUp(routineExercise) },
                                onMoveDown: { moveDown(routineExercise) },
                                onAddSet: { addSet(to: routineExercise) },
                                onDeleteSet: { template in deleteSet(template, from: routineExercise) }
                            )
                        }
                    }

                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(routine.name.isEmpty ? "New Routine" : routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                FolderPickerSheet(selectedFolder: $routine.folder)
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerSheet { exercise in
                    addExercise(exercise)
                }
            }
        }
    }

    // MARK: - Exercises

    private func addExercise(_ exercise: Exercise) {
        let routineExercise = RoutineExercise(orderIndex: sortedExercises.count, exercise: exercise)
        modelContext.insert(routineExercise)
        routineExercise.routine = routine
    }

    private func remove(_ routineExercise: RoutineExercise) {
        let group = routineExercise.supersetGroup
        modelContext.delete(routineExercise)
        if let group {
            dissolveGroupIfSingle(group)
        }
        reindex()
    }

    private func moveUp(_ routineExercise: RoutineExercise) {
        guard let index = sortedExercises.firstIndex(where: { $0.id == routineExercise.id }), index > 0 else { return }
        swapOrder(sortedExercises[index], sortedExercises[index - 1])
    }

    private func moveDown(_ routineExercise: RoutineExercise) {
        guard let index = sortedExercises.firstIndex(where: { $0.id == routineExercise.id }),
              index < sortedExercises.count - 1 else { return }
        swapOrder(sortedExercises[index], sortedExercises[index + 1])
    }

    private func swapOrder(_ a: RoutineExercise, _ b: RoutineExercise) {
        let temp = a.orderIndex
        a.orderIndex = b.orderIndex
        b.orderIndex = temp
    }

    private func reindex() {
        for (index, routineExercise) in sortedExercises.enumerated() {
            routineExercise.orderIndex = index
        }
    }

    // MARK: - Supersets (PRD §7.8) — logic shared with the active workout, see SupersetGrouping.swift

    private func group(_ a: RoutineExercise, with b: RoutineExercise) {
        SupersetGrouping.group(a, with: b, among: sortedExercises)
    }

    private func ungroup(_ routineExercise: RoutineExercise) {
        SupersetGrouping.ungroup(routineExercise, among: sortedExercises)
    }

    private func dissolveGroupIfSingle(_ group: String) {
        SupersetGrouping.dissolveIfSingle(group, among: sortedExercises)
    }

    // MARK: - Set templates

    private func addSet(to routineExercise: RoutineExercise) {
        let templates = (routineExercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let next = RoutineSetTemplate(
            orderIndex: templates.count,
            targetWeightKg: templates.last?.targetWeightKg,
            targetReps: templates.last?.targetReps
        )
        modelContext.insert(next)
        next.routineExercise = routineExercise
    }

    private func deleteSet(_ template: RoutineSetTemplate, from routineExercise: RoutineExercise) {
        modelContext.delete(template)
        let remaining = (routineExercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }
        for (index, template) in remaining.enumerated() {
            template.orderIndex = index
        }
    }

    // MARK: - Lifecycle

    private func save() {
        routine.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }

    /// A routine created via "+ New Routine" is inserted immediately (so the
    /// editor has something to bind to) — if the user backs out without
    /// naming it or adding anything, that empty row shouldn't linger.
    private func cancel() {
        if routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sortedExercises.isEmpty {
            modelContext.delete(routine)
        }
        dismiss()
    }
}
