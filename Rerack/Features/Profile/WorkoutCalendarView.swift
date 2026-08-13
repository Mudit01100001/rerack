import SwiftUI
import SwiftData

/// PRD §9.6 Calendar tile: month grid, days with workouts marked, tap a day
/// to see them.
struct WorkoutCalendarView: View {
    @Environment(\.unitPreference) private var unit
    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday, matching the streak rule (§13.5)
        return calendar
    }

    private var workoutsByDay: [Date: [Workout]] {
        Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.startedAt) }
    }

    /// Leading `nil`s pad the grid so the 1st lands under the right weekday.
    private var gridDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: leading) + days
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            HStack(spacing: 0) {
                ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            .padding(.horizontal, 8)

            if let selectedDay, let items = workoutsByDay[selectedDay], !items.isEmpty {
                List(items) { workout in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title).font(.subheadline.weight(.medium))
                        Text("\(Weight.formatTotal(kg: ProfileStats.volume(of: workout), in: unit)) · \(ProfileStats.completedSets(in: workout).count) sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
            }
        }
        .padding(.top, 8)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func dayCell(_ day: Date) -> some View {
        let hasWorkout = workoutsByDay[day] != nil
        let isSelected = selectedDay == day
        return Button {
            selectedDay = hasWorkout ? day : nil
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    Circle()
                        .fill(hasWorkout ? Color.accentColor.opacity(isSelected ? 1 : 0.35) : .clear)
                        .frame(width: 32, height: 32)
                )
                .foregroundStyle(hasWorkout && isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            month = next
            selectedDay = nil
        }
    }
}
