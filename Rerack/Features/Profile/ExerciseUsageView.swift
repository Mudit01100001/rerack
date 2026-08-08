import SwiftUI
import SwiftData

/// PRD §9.6 Exercises tile: your library sorted by most-performed. Distinct
/// from the Exercise Library (§9.1), which is alphabetical and exists to
/// find something — this exists to see what you actually train.
struct ExerciseUsageView: View {
    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    @Query(filter: #Predicate<Exercise> { !$0.isArchived })
    private var exercises: [Exercise]

    @State private var selected: Exercise?

    private var usage: [ProfileStats.ExerciseUsage] {
        ProfileStats.exerciseUsage(workouts)
    }

    var body: some View {
        Group {
            if usage.isEmpty {
                ContentUnavailableView(
                    "No exercises logged yet",
                    systemImage: "list.bullet",
                    description: Text("Once you've trained, your most-used movements land here.")
                )
            } else {
                List(usage) { item in
                    Button {
                        selected = exercises.first { $0.id == item.exerciseID }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(.primary)
                                if let last = item.lastPerformed {
                                    Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(item.sessionCount)×")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { ExerciseDetailView(exercise: $0) }
    }
}
