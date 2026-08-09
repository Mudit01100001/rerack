import SwiftUI
import SwiftData

/// PRD §9.6. Full workout-summary cards (duration/volume/PR badges/top
/// exercises) ship in M7+ — M3 shows enough to confirm a finished workout
/// actually landed here. A *live* workout deliberately isn't listed: it's
/// reachable via the persistent banner / full-screen cover, not the log.
struct HomeView: View {
    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Start a workout from the Workout tab and it'll show up here.")
                    )
                } else {
                    List(workouts) { workout in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title)
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(workout.startedAt, style: .date)
                                Text("·")
                                Text("\(Int(workout.cachedVolumeKg)) kg")
                                Text("·")
                                Text("\(workout.cachedSetCount) sets")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Workout.self], inMemory: true)
}
