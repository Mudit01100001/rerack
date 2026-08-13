import SwiftUI
import SwiftData

/// PRD §9.6. The dashboard: headline stats, a consistency grid, muscle
/// balance, then recent sessions.
///
/// A *live* workout deliberately isn't listed here. It's reachable from the
/// pill above the tab bar, not the log, so history stays a record of what
/// actually finished.
struct HomeView: View {
    @Environment(\.unitPreference) private var unit
    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    private var streaks: ProfileStats.Streaks {
        ProfileStats.streaks(from: workouts)
    }

    private var volumeByDay: [Date: Double] {
        let calendar = Calendar.current
        return workouts.reduce(into: [:]) { totals, workout in
            let day = calendar.startOfDay(for: workout.startedAt)
            totals[day, default: 0] += ProfileStats.volume(of: workout)
        }
    }

    private var recentMuscleVolume: [ProfileStats.MuscleVolume] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return ProfileStats.volumeByMuscle(workouts.filter { $0.startedAt >= cutoff })
    }

    private var totalVolume: Double {
        workouts.reduce(0) { $0 + ProfileStats.volume(of: $1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    if workouts.isEmpty {
                        emptyState
                    } else {
                        statTiles
                        consistencyCard
                        MuscleBalanceCard(volumeByMuscle: recentMuscleVolume)
                        recentSessions
                        footerLine
                    }
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
        }
    }

    // MARK: - Stats

    private var statTiles: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: DS.Space.xs), GridItem(.flexible(), spacing: DS.Space.xs)],
            spacing: DS.Space.xs
        ) {
            tile("Workouts", "\(workouts.count)")
            tile("Total volume", Weight.formatTotal(kg: totalVolume, in: unit))
            tile("Current streak", "\(streaks.current) wk")
            tile("Longest streak", "\(streaks.longest) wk")
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                .foregroundStyle(.secondary)
            Text(value)
                .dsFont(DS.TypeScale.heading, relativeTo: .title3, weight: .semibold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.sm)
        .dsCard(radius: DS.Radius.medium)
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Consistency")
                    .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                Spacer()
                Text("\(volumeByDay.count) days trained")
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
            }
            ContributionGrid(volumeByDay: volumeByDay)
        }
        .padding(DS.Space.md)
        .dsCard()
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)

            ForEach(Array(workouts.prefix(6).enumerated()), id: \.element.id) { index, workout in
                if index > 0 { Divider().padding(.leading, DS.Space.md) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.routineNameSnapshot ?? workout.title)
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    HStack(spacing: DS.Space.xxs) {
                        Text(workout.startedAt, style: .date)
                        Text("·")
                        Text(Weight.formatTotal(kg: workout.cachedVolumeKg, in: unit))
                        Text("·")
                        Text("\(workout.cachedSetCount) sets")
                    }
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs + 2)
            }
        }
        .padding(.bottom, DS.Space.xs)
        .dsCard()
    }

    /// One line of context at the bottom, computed from real totals. Comparing
    /// against something physical makes a number people have no intuition for
    /// ("48,200 kg") mean something.
    private var footerLine: some View {
        Text(comparisonLine)
            .dsFont(DS.TypeScale.caption, relativeTo: .caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.xxs)
            .padding(.bottom, DS.Space.sm)
    }

    private var comparisonLine: String {
        guard totalVolume > 0 else { return "" }
        guard let match = AnimalLadder.match(volumeKg: totalVolume) else { return "" }
        return "All told, you've moved \(match.headline.lowercased())."
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No workouts yet",
            systemImage: "figure.strengthtraining.traditional",
            description: Text("Start a workout from the Workout tab and it'll show up here.")
        )
        .padding(.top, DS.Space.xl)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Workout.self], inMemory: true)
}
