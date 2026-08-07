import SwiftUI
import SwiftData

/// PRD §9.1: "name (required), equipment, primary muscle (required),
/// secondary muscles (multi-select, optional). Custom exercises are
/// visually indistinguishable from built-ins once created."
struct AddCustomExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var equipment: Equipment = .barbell
    @State private var primaryMuscle: Muscle = .chest
    @State private var secondaryMuscles: Set<Muscle> = []

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Cable Chest Press", text: $name)
                }

                Section("Equipment") {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { eq in
                            Text(eq.displayName).tag(eq)
                        }
                    }
                }

                Section("Primary Muscle") {
                    Picker("Primary Muscle", selection: $primaryMuscle) {
                        ForEach(Muscle.allCases) { muscle in
                            Text(muscle.displayName).tag(muscle)
                        }
                    }
                    .onChange(of: primaryMuscle) {
                        secondaryMuscles.remove(primaryMuscle)
                    }
                }

                Section("Secondary Muscles") {
                    ForEach(Muscle.allCases.filter { $0 != primaryMuscle }) { muscle in
                        Toggle(muscle.displayName, isOn: secondaryBinding(for: muscle))
                    }
                }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func secondaryBinding(for muscle: Muscle) -> Binding<Bool> {
        Binding(
            get: { secondaryMuscles.contains(muscle) },
            set: { isOn in
                if isOn {
                    secondaryMuscles.insert(muscle)
                } else {
                    secondaryMuscles.remove(muscle)
                }
            }
        )
    }

    private func save() {
        let exercise = Exercise(
            name: trimmedName,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: Array(secondaryMuscles),
            isCustom: true
        )
        modelContext.insert(exercise)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddCustomExerciseView()
        .modelContainer(for: [Exercise.self], inMemory: true)
}
