import SwiftUI
import SwiftData

/// PRD §9.6. M1 ships the empty state only — the reverse-chronological
/// workout log itself depends on the active workout screen (M3).
struct HomeView: View {
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Start a routine from the Workout tab and it'll show up here.")
                    )
                } else {
                    List(workouts) { workout in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title)
                                .font(.headline)
                            Text(workout.startedAt, style: .date)
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
