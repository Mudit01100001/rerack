import SwiftUI

/// A minimal stand-in for the full Exercise Detail screen (PRD §9.2), which
/// ships in M6 with Summary/History tabs, the progress graph, and PR cards.
/// Deliberately thin for M1 — just enough to confirm what got tapped.
///
/// No image, no video, no reserved space for either: PRD §6.2 removes
/// exercise media from the product entirely, not just from M1.
struct ExerciseQuickDetailView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Equipment", value: exercise.equipment.displayName)
                    LabeledContent("Primary Muscle", value: exercise.primaryMuscle.displayName)
                    if !exercise.secondaryMuscles.isEmpty {
                        LabeledContent(
                            "Secondary",
                            value: exercise.secondaryMuscles.map(\.displayName).joined(separator: ", ")
                        )
                    }
                    if exercise.isCustom {
                        LabeledContent("Source", value: "Custom")
                    }
                }

                Section {
                    Text("Summary, history, and progress graphs ship in M6–M8.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
