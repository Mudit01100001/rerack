import SwiftUI
import SwiftData

/// Browse and import the bundled starter splits (`RoutineTemplates`). Reached
/// from the Workout tab, and the answer to a first launch showing an empty
/// routine list.
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selected: RoutineTemplate?

    var body: some View {
        List {
            Section {
                ForEach(RoutineTemplate.all) { template in
                    Button {
                        selected = template
                    } label: {
                        row(template)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Importing copies the workouts into your library. Nothing stays linked — edit or delete them like any workout you built yourself.")
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { template in
            TemplateDetailView(template: template) { dismiss() }
        }
    }

    private func row(_ template: RoutineTemplate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: DS.Space.xs) {
                Text(template.title)
                    .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(.primary)
                if template.isRecommended {
                    Text("RECOMMENDED")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(template.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Text("\(template.daysPerWeek) · \(template.routines.count) workouts · \(template.exerciseCount) exercises")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// The detail sheet — everything the template contains, before you commit to
/// importing it. Showing the full contents rather than a blurb is the point:
/// an import that drops six routines into your library shouldn't be a
/// surprise.
private struct TemplateDetailView: View {
    let template: RoutineTemplate
    let onImported: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var importResult: TemplateImporter.Result?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(template.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(template.routines.enumerated()), id: \.offset) { _, routine in
                    Section(routine.name) {
                        ForEach(Array(routine.exercises.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.exerciseName)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(setSummary(entry))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if let note = entry.note {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { runImport() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Imported", isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("Done") {
                    importResult = nil
                    dismiss()
                    onImported()
                }
            } message: {
                if let importResult {
                    Text(message(for: importResult))
                }
            }
        }
    }

    /// `3 × 10` when every set matches, `20×5, 18×9, 18×9` when they don't —
    /// collapsing a varied progression into "3 sets" would hide the thing
    /// that makes the template worth importing.
    private func setSummary(_ entry: RoutineTemplate.ExerciseEntry) -> String {
        let targets = entry.sets
        guard let first = targets.first else { return "" }
        let uniform = targets.allSatisfy { $0.weightKg == first.weightKg && $0.reps == first.reps }
        if uniform {
            let reps = first.reps.map(String.init) ?? "—"
            guard let weight = first.weightKg else { return "\(targets.count) × \(reps)" }
            return "\(targets.count) × \(reps) @ \(formatted(weight)) kg"
        }
        return targets.map { target in
            let reps = target.reps.map(String.init) ?? "—"
            guard let weight = target.weightKg else { return reps }
            return "\(formatted(weight))×\(reps)"
        }.joined(separator: ", ")
    }

    private func message(for result: TemplateImporter.Result) -> String {
        var text = "\(result.routinesCreated) workout\(result.routinesCreated == 1 ? "" : "s") added to a “\(template.title)” folder."
        if !result.unmatchedExercises.isEmpty {
            let unique = Array(Set(result.unmatchedExercises)).sorted()
            text += "\n\nSkipped (not in your exercise library): \(unique.joined(separator: ", "))."
        }
        return text
    }

    private func runImport() {
        importResult = TemplateImporter.import(template, context: modelContext)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
