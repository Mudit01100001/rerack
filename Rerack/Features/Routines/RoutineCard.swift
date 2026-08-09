import SwiftUI

/// PRD §9.3: "name, exercise count, derived muscle chips, last-performed
/// relative date, Start Workout button. Long-press → Edit / Duplicate /
/// Move to folder / Delete." Muscle chips are computed from the exercises'
/// primary muscles at render time — never stored — so they can't go stale
/// when an exercise is swapped.
///
/// Fixed from M2: the whole card used to open the editor on tap regardless
/// of where you touched, which is why "Start Workout" appeared broken — it
/// was disabled (no active workout screen existed yet), and the tap fell
/// through to the card's own gesture. Tapping the card (or the button) now
/// starts the routine; editing only lives behind long-press.
struct RoutineCard: View {
    let routine: Routine
    let isStartDisabled: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var exercises: [RoutineExercise] {
        (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var derivedMuscles: [Muscle] {
        var seen = Set<Muscle>()
        return exercises.compactMap(\.exercise?.primaryMuscle).filter { seen.insert($0).inserted }
    }

    private var canStart: Bool { !exercises.isEmpty && !isStartDisabled }

    @Environment(\.editMode) private var editMode

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs + 2) {
            Text(routine.name)
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)

            // While editing, the row is a thing you're *moving*, not one
            // you're reading. Exercise count, muscles, last-performed and the
            // Start button all collapse — the drag handle needs a short,
            // uniform row to sit against, and none of that detail helps you
            // decide where a day belongs in the week.
            if !isEditing {
                HStack(spacing: DS.Space.xxs) {
                    Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
                    if !derivedMuscles.isEmpty {
                        Text("·")
                        Text(derivedMuscles.prefix(3).map(\.displayName).joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                .foregroundStyle(.secondary)

                if let last = routine.lastPerformedAt {
                    Text("Last: \(last.formatted(.relative(presentation: .named)))")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.tertiary)
                }

                Button(action: onStart) {
                    Label("Start Workout", systemImage: "play.fill")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                }
                .buttonStyle(.bordered)
                .disabled(!canStart)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, DS.Space.xxs)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing, canStart else { return }
            onStart()
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
