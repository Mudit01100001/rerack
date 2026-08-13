import SwiftUI
import SwiftData
import Charts

/// PRD §9.6 Statistics tile.
struct StatisticsView: View {
    @Environment(\.unitPreference) private var unit
    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    /// §9.3: deload/testing sessions stay in your log but out of anything
    /// that reads as progress.
    private var tracked: [Workout] { workouts.filter(\.trackedAsProgress) }

    private var totalVolume: Double { workouts.reduce(0) { $0 + ProfileStats.volume(of: $1) } }
    private var totalHours: Double { workouts.reduce(0) { $0 + ProfileStats.duration(of: $1) } / 3600 }
    private var averageDuration: TimeInterval {
        workouts.isEmpty ? 0 : workouts.reduce(0) { $0 + ProfileStats.duration(of: $1) } / Double(workouts.count)
    }

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "Nothing to summarise yet",
                    systemImage: "chart.bar",
                    description: Text("Finish a workout and your stats will build up here.")
                )
            } else {
                Section("Lifetime") {
                    row("Workouts", "\(workouts.count)")
                    row("Volume", Weight.formatTotal(kg: totalVolume, in: unit))
                    row("Hours", String(format: "%.1f", totalHours))
                    row("Average duration", formattedDuration(averageDuration))
                }

                Section {
                    let streaks = ProfileStats.streaks(from: tracked)
                    row("Current", "\(streaks.current) week\(streaks.current == 1 ? "" : "s")")
                    row("Longest", "\(streaks.longest) week\(streaks.longest == 1 ? "" : "s")")
                } header: {
                    HStack(spacing: 4) {
                        Text("Streak")
                        ExplainerButton(term: .streak)
                    }
                }

                let byMuscle = ProfileStats.volumeByMuscle(tracked)
                if !byMuscle.isEmpty {
                    Section("Volume by muscle group") {
                        Chart(byMuscle) { item in
                            BarMark(
                                x: .value("Volume", item.volumeKg),
                                y: .value("Muscle", item.muscle.displayName)
                            )
                        }
                        .frame(height: max(CGFloat(byMuscle.count) * 26, 120))
                    }
                }

                let usage = ProfileStats.exerciseUsage(tracked)
                if !usage.isEmpty {
                    Section("Most performed") {
                        ForEach(usage.prefix(5)) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text("\(item.sessionCount)×")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 3600 > 0 ? total / 3600 : total / 60, total / 3600 > 0 ? (total % 3600) / 60 : total % 60)
    }
}
