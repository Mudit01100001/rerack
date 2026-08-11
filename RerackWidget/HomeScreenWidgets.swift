import WidgetKit
import SwiftUI

// MARK: - Timeline

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // The gallery preview must never show a real user's data, and must
        // never be empty either.
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : MainActor.assumeIsolated { WidgetDataSource.load() }
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: MainActor.assumeIsolated { WidgetDataSource.load() })
        // Nothing here changes on a schedule — it changes when the user
        // trains. The app reloads timelines on finish; this hourly refresh is
        // only a backstop so a stale "trained today" square self-corrects
        // after midnight without the app being opened.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

// MARK: - Day selector

/// Pick today's session straight from the home screen. Each row deep-links
/// to that specific workout, so the whole flow is one tap from the lock
/// screen instead of app -> tab -> split -> day.
struct WorkoutSelectorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutSelector", provider: SnapshotProvider()) { entry in
            SelectorView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Workout")
        .description("Start any day from your current split.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct SelectorView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var visibleDays: [WidgetSnapshot.Day] {
        Array(snapshot.days.prefix(family == .systemLarge ? 6 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.splitName ?? "Workouts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if snapshot.days.count > visibleDays.count {
                    Text("+\(snapshot.days.count - visibleDays.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if snapshot.hasLiveWorkout {
                // §6: you can't start a second workout, so don't offer to.
                Link(destination: WorkoutDeepLink.active) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("In progress").font(.caption2).opacity(0.85)
                            Text(snapshot.liveWorkoutTitle ?? "Workout")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 0)
            } else if visibleDays.isEmpty {
                Link(destination: WorkoutDeepLink.workoutTab) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workouts yet").font(.subheadline.weight(.medium))
                        Text("Import a template to get started.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(visibleDays) { day in
                        Link(destination: WorkoutDeepLink.start(routineID: day.id)) {
                            dayRow(day)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func dayRow(_ day: WidgetSnapshot.Day) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(day.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle(day))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func subtitle(_ day: WidgetSnapshot.Day) -> String {
        let count = "\(day.exerciseCount) exercise\(day.exerciseCount == 1 ? "" : "s")"
        guard let last = day.lastPerformed else { return count }
        return "\(count) · \(last.formatted(.relative(presentation: .numeric)))"
    }
}

// MARK: - Consistency

/// Streak, this week's count, and the contribution grid — the same "did I
/// show up" question the Home tab answers, at a glance.
struct TrainingStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrainingStats", provider: SnapshotProvider()) { entry in
            StatsView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Consistency")
        .description("Your streak and the last five weeks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatsView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Link(destination: WorkoutDeepLink.workoutTab) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.currentStreakWeeks)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(snapshot.currentStreakWeeks == 1 ? "week" : "weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(snapshot.workoutsThisWeek) this week · \(snapshot.totalWorkouts) total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
                grid
            }
        }
    }

    /// Columns are weeks, rows are weekdays — same orientation as the Home
    /// tab's grid, so the two read as the same object at different sizes.
    private var grid: some View {
        let columns = stride(from: 0, to: 35, by: 7).map { Array(snapshot.recentDays[$0..<min($0 + 7, 35)]) }
        return HStack(spacing: 3) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, trained in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(trained ? Color.accentColor : Color.primary.opacity(0.12))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)
    }

    private var cell: CGFloat { family == .systemSmall ? 8 : 10 }
}
