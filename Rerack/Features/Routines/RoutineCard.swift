import SwiftUI

/// PRD §9.3: "name, exercise count, derived muscle chips, last-performed
/// relative date, Start Routine button." Muscle chips are computed from the
/// exercises' primary muscles at render time — never stored — so they can't
/// go stale when an exercise is swapped.
struct RoutineCard: View {
    let routine: Routine

    private var exercises: [RoutineExercise] {
        (routine.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private var derivedMuscles: [Muscle] {
        var seen = Set<Muscle>()
        return exercises.compactMap(\.exercise?.primaryMuscle).filter { seen.insert($0).inserted }
    }

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

            Button {
                // Starting a routine ships in M3 (PRD §7) — the active
                // workout screen doesn't exist yet for this button to open.
            } label: {
                Label("Start Routine", systemImage: "play.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
