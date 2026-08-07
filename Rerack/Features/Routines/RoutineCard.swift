import SwiftUI

/// PRD §9.3: "name, exercise count, derived muscle chips, last-performed
/// relative date, Start Routine button. Long-press → Edit / Duplicate /
/// Move to folder / Delete." Muscle chips are computed from the exercises'
/// primary muscles at render time — never stored — so they can't go stale
/// when an exercise is swapped.
///
/// Fixed from M2: the whole card used to open the editor on tap regardless
/// of where you touched, which is why "Start Routine" appeared broken — it
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(routine.name)
                .font(.headline)

            HStack(spacing: 4) {
                Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")")
                if !derivedMuscles.isEmpty {
                    Text("·")
                    Text(derivedMuscles.prefix(3).map(\.displayName).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let last = routine.lastPerformedAt {
                Text("Last: \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button(action: onStart) {
                Label("Start Routine", systemImage: "play.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(!canStart)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if canStart { onStart() }
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
