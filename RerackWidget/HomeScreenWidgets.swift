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
            // `fixedSize` so the header can't be compressed away when the
            // rows below want more room than the family has. Widgets don't
            // scroll, so something has to lose, and it shouldn't be the
            // label that says which split you're looking at.
            HStack(spacing: 4) {
                Text((snapshot.splitName ?? "Workouts").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if snapshot.days.count > visibleDays.count {
                    Text("+\(snapshot.days.count - visibleDays.count) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

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

    /// How many weeks fit across. The grid then sizes its cells to whatever
    /// space is actually available, rather than a fixed cell size that left
    /// two-thirds of a medium widget empty.
    private var weeks: Int { family == .systemSmall ? 7 : 17 }

    var body: some View {
        Link(destination: WorkoutDeepLink.workoutTab) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONSISTENCY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.currentStreakWeeks)")
                        .font(.system(size: family == .systemSmall ? 26 : 30, weight: .bold, design: .rounded))
                    Text(snapshot.currentStreakWeeks == 1 ? "wk streak" : "wk streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if family != .systemSmall {
                        Spacer()
                        Text("\(snapshot.workoutsThisWeek) this week · \(snapshot.totalWorkouts) total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                ContributionGridView(days: snapshot.recentDays, weeks: weeks)
            }
        }
    }
}

/// Columns are weeks, rows are weekdays — same orientation as the Home tab's
/// grid, so the two read as one object at two sizes.
///
/// Cell size is derived from the space available in both axes, so the grid
/// spans the full width of whatever family it lands in and still can't
/// overflow vertically.
private struct ContributionGridView: View {
    let days: [Bool]
    let weeks: Int

    private let spacing: CGFloat = 2.5

    private var columns: [[Bool]] {
        let needed = weeks * 7
        let tail = days.count >= needed ? Array(days.suffix(needed)) : days
        return stride(from: 0, to: tail.count, by: 7).map {
            Array(tail[$0..<min($0 + 7, tail.count)])
        }
    }

    /// Rows are weekdays, Monday first — `WidgetDataSource.recentDays` builds
    /// the window from a `firstWeekday = 2` week boundary, so row 0 is always
    /// a Monday and these labels can't drift out of sync with the data.
    private let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]
    private let labelWidth: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let count = max(columns.count, 1)
            let gridWidth = geometry.size.width - labelWidth - spacing
            // Width is satisfied first and height only clamps the cell's
            // *height*. Sizing both axes off `min(byWidth, byHeight)` meant a
            // height-constrained family shrank its cells and left a dead strip
            // down the right-hand side — most visible at 2x2, where the grid
            // stopped well short of the card edge.
            let cellWidth = max((gridWidth - spacing * CGFloat(count - 1)) / CGFloat(count), 2)
            let cellHeight = max(min((geometry.size.height - spacing * 6) / 7, cellWidth), 2)
            let radius = min(cellWidth, cellHeight) * 0.22

            HStack(spacing: spacing) {
                VStack(spacing: spacing) {
                    ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                        Text(initial)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: labelWidth, height: cellHeight)
                    }
                }

                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, trained in
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(trained ? Color.accentColor : Color.primary.opacity(0.13))
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
