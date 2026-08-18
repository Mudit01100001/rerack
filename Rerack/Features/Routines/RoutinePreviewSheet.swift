import SwiftUI
import SwiftData

/// What a workout tile opens when you tap it.
///
/// Tapping the tile and pressing its Start Workout button used to be the same
/// action — `RoutineCard` put `onStart()` on both the button and a
/// `contentShape` tap gesture covering the whole row. That left no way to
/// *look at* a day before committing to it, which is the more common intent:
/// you tap a split to remember what's in it far more often than you tap it
/// meaning "begin now, full screen, timer running."
///
/// Now the tile previews and the button commits. Start is still one tap away
/// from here, so nothing got slower.
struct RoutinePreviewSheet: View {
    let routine: Routine
    let isStartDisabled: Bool
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.unitPreference) private var unit

    private var exercises: [RoutineExercise] {
        (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var canStart: Bool { !exercises.isEmpty && !isStartDisabled }

    private var totalSets: Int {
        exercises.reduce(0) { $0 + ($1.setTemplates ?? []).count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    summaryRow

                    if exercises.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: DS.Space.xs) {
                            ForEach(exercises) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    }
                }
                .padding(DS.Space.md)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                startButton
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryRow: some View {
        HStack(spacing: DS.Space.lg) {
            stat("\(exercises.count)", "Exercise\(exercises.count == 1 ? "" : "s")")
            stat("\(totalSets)", "Set\(totalSets == 1 ? "" : "s")")
            if let last = routine.lastPerformedAt {
                stat(last.formatted(.relative(presentation: .named)), "Last done")
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .dsFont(DS.TypeScale.heading, relativeTo: .title3, weight: .semibold, design: .rounded)
            Text(label)
                .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.xs) {
            Image(systemName: "square.dashed")
                .dsFont(DS.TypeScale.title, relativeTo: .largeTitle)
                .foregroundStyle(.tertiary)
            Text("No exercises yet")
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
            Text("Long-press the tile and choose Edit to add some.")
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }

    private func exerciseRow(_ exercise: RoutineExercise) -> some View {
        let templates = (exercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }
        return HStack(alignment: .top, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Space.xxs) {
                    if let label = SupersetGrouping.label(for: exercise, among: exercises) {
                        Text(label)
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Text(exercise.exercise?.name ?? "Exercise")
                        .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .medium)
                }
                Text(targetSummary(templates))
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: DS.Radius.medium, style: .continuous)
        )
    }

    /// "3 × 10 · 60 kg" when the plan is uniform, "4 sets" when it isn't —
    /// spelling out four different set targets in a preview is noise.
    private func targetSummary(_ templates: [RoutineSetTemplate]) -> String {
        guard !templates.isEmpty else { return "No sets planned" }
        let reps = Set(templates.compactMap(\.targetReps))
        let weights = Set(templates.compactMap(\.targetWeightKg))
        guard reps.count == 1, let onlyReps = reps.first else {
            return "\(templates.count) set\(templates.count == 1 ? "" : "s")"
        }
        var summary = "\(templates.count) × \(onlyReps)"
        if weights.count == 1, let onlyWeight = weights.first, onlyWeight > 0 {
            summary += " · \(Weight.format(kg: onlyWeight, in: unit, includeUnit: true))"
        }
        return summary
    }

    private var startButton: some View {
        Button {
            Haptics.play(.setCompleted)
            // Dismiss first: presenting the full-screen workout from under a
            // sheet that is still on screen races the two transitions and can
            // leave the workout behind the sheet.
            dismiss()
            onStart()
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canStart)
        .padding(.horizontal, DS.Space.md)
        .padding(.bottom, DS.Space.xs)
        .background(.bar)
    }
}
