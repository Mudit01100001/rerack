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
/// through to the card's own gesture.
///
/// That fix then overcorrected: the tap and the button became the *same*
/// action, so there was no way to look at a day without starting it. Tapping
/// the tile now previews (`onPreview`); the button commits (`onStart`);
/// editing stays behind long-press.
struct RoutineCard: View {
    let routine: Routine
    let isStartDisabled: Bool
    let onStart: () -> Void
    /// Item 1: a tap on the tile body opens the day rather than starting it.
    let onPreview: () -> Void
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

    /// Previewing is allowed even when starting isn't — reading the plan
    /// while another workout is live is reasonable, and an empty day is
    /// exactly the one you want to open and fill.
    private func openPreview() {
        guard !isEditing else { return }
        Haptics.play(.selection)
        onPreview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs + 2) {
            // An explicit button, not a tap gesture on the row.
            //
            // A `List` row containing exactly one `Button` routes a tap
            // anywhere in the row to that button — which is *why* tapping the
            // tile and pressing Start Workout did the same thing, and why
            // moving the row's `.onTapGesture` to `onPreview` changed nothing:
            // the tap never reached the gesture. Two buttons make the row
            // ambiguous, so SwiftUI hit-tests each one properly.
            Button(action: openPreview) {
                Text(routine.name)
                    .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEditing)

            // While editing, the row is a thing you're *moving*, not one
            // you're reading. Exercise count, muscles, last-performed and the
            // Start button all collapse — the drag handle needs a short,
            // uniform row to sit against, and none of that detail helps you
            // decide where a day belongs in the week.
            if !isEditing {
                Button(action: openPreview) {
                    HStack(spacing: DS.Space.xxs) {
                        Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
                        if !derivedMuscles.isEmpty {
                            Text("·")
                            Text(derivedMuscles.prefix(3).map(\.displayName).joined(separator: ", "))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let last = routine.lastPerformedAt {
                    Text("Last: \(last.formatted(.relative(presentation: .named)))")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    Haptics.play(.setCompleted)
                    onStart()
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                }
                .buttonStyle(.bordered)
                .disabled(!canStart)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, DS.Space.xxs)
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
