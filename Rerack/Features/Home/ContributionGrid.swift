import SwiftUI

/// A GitHub-style contribution grid: one cell per day, columns are weeks,
/// rows are weekdays.
///
/// Deliberately *not* a bar chart. §9.6's activity graph already answers "how
/// much" over time; this answers "did I show up," which is a different
/// question and the one that actually predicts progress. A year of a
/// consistent three-day habit looks obviously different from a month of
/// heroics followed by nothing, and only this shape shows that.
struct ContributionGrid: View {
    /// Days that had at least one workout, mapped to that day's volume, so
    /// intensity can shade the cell.
    let volumeByDay: [Date: Double]
    var weeks: Int = 26

    private let cell: CGFloat = 11
    private let spacing: CGFloat = 3
    /// Monday first — `columns` builds each week from a `firstWeekday = 2`
    /// interval, so row 0 is always a Monday.
    private let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    /// Columns of 7 days, oldest first, ending on today's week.
    private var columns: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { weeksBack in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: thisWeekStart) else { return nil }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        }
    }

    /// Shading is relative to the user's own best day, not an absolute scale.
    /// A fixed threshold would leave a beginner's grid permanently pale and a
    /// stronger lifter's permanently saturated.
    private var peakVolume: Double {
        max(volumeByDay.values.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .top, spacing: spacing) {
                // Item 15: the same weekday gutter the widget carries, so the
                // two grids read as one object. Without it a row of squares
                // is unreadable — you can see *that* you trained without
                // being able to see *which day* you trained.
                VStack(spacing: spacing) {
                    ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                        Text(initial)
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .medium)
                            .foregroundStyle(.tertiary)
                            .frame(width: 10, height: cell)
                    }
                }
                .padding(.vertical, 2)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { index, week in
                                VStack(spacing: spacing) {
                                    ForEach(week, id: \.self) { day in
                                        cellView(for: day)
                                    }
                                }
                                .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // Opens on the present, not six months ago.
                    .onAppear { proxy.scrollTo(columns.count - 1, anchor: .trailing) }
                }
            }

            HStack(spacing: DS.Space.xxs) {
                Text("Less")
                ForEach([0.0, 0.25, 0.55, 0.85], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(colour(forIntensity: level))
                        .frame(width: cell * 0.8, height: cell * 0.8)
                }
                Text("More")
            }
            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func cellView(for day: Date) -> some View {
        let isFuture = day > Date()
        let volume = volumeByDay[calendar.startOfDay(for: day)] ?? 0
        let intensity = volume > 0 ? 0.25 + 0.75 * min(volume / peakVolume, 1) : 0

        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(colour(forIntensity: intensity))
            .frame(width: cell, height: cell)
            // Future days in the current week are drawn but dimmed, so the
            // grid doesn't end on a ragged edge mid-week.
            .opacity(isFuture ? 0.35 : 1)
            .accessibilityLabel(
                volume > 0
                    ? "\(day.formatted(date: .abbreviated, time: .omitted)), \(Int(volume)) kilograms"
                    : "\(day.formatted(date: .abbreviated, time: .omitted)), rest day"
            )
    }

    private func colour(forIntensity intensity: Double) -> Color {
        intensity <= 0
            ? Color.primary.opacity(0.08)
            : Color.accentColor.opacity(0.25 + 0.75 * intensity)
    }
}
