import Foundation
import SwiftData

/// PRD §9.6 / §13.5. Aggregations behind the Profile screen and its
/// dashboard tiles. Pure functions over already-fetched workouts so the
/// views don't each re-derive (and potentially disagree about) totals.
@MainActor
enum ProfileStats {
    /// PRD §13.5: **consecutive weeks (Mon–Sun) containing at least one
    /// workout**, counting back from the current week — deliberately not
    /// days. A daily streak on a strength app punishes rest days, which is
    /// backwards: rest is when the adaptation happens. The `?` explainer
    /// (§10.3) says exactly this to the user.
    ///
    /// The current week counts as "alive" if it has a workout; if it
    /// doesn't, the streak is measured from last week instead, so the
    /// counter doesn't drop to zero every Monday morning before you train.
    struct Streaks {
        let current: Int
        let longest: Int
    }

    static func streaks(from workouts: [Workout], calendar: Calendar = .current) -> Streaks {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2 // Monday

        let weeks = Set(workouts.compactMap { workout -> Date? in
            weekCalendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start
        })
        guard !weeks.isEmpty else { return Streaks(current: 0, longest: 0) }

        let sorted = weeks.sorted()

        // Longest: walk the sorted weeks, breaking whenever two adjacent
        // entries aren't exactly one week apart.
        var longest = 1
        var run = 1
        for i in 1..<max(sorted.count, 1) where sorted.count > 1 {
            let expected = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: sorted[i - 1])
            if let expected, weekCalendar.isDate(sorted[i], equalTo: expected, toGranularity: .weekOfYear) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        // Current: count back from this week, or last week if this one is
        // still empty.
        guard let thisWeek = weekCalendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return Streaks(current: 0, longest: longest)
        }
        var cursor = weeks.contains(thisWeek)
            ? thisWeek
            : weekCalendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        var current = 0
        while let week = cursor, weeks.contains(week) {
            current += 1
            cursor = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }

        return Streaks(current: current, longest: longest)
    }

    static func completedSets(in workout: Workout) -> [SetLog] {
        (workout.exercises ?? []).flatMap { $0.sets ?? [] }.filter(\.isCompleted)
    }

    static func volume(of workout: Workout) -> Double {
        completedSets(in: workout).reduce(0) { $0 + $1.setVolumeKg }
    }

    static func duration(of workout: Workout) -> TimeInterval {
        guard let endedAt = workout.endedAt else { return 0 }
        return endedAt.timeIntervalSince(workout.startedAt)
    }

    struct MuscleVolume: Identifiable {
        var id: Muscle { muscle }
        let muscle: Muscle
        let volumeKg: Double
    }

    /// Attributed by each set's exercise `primaryMuscle` only. Splitting
    /// credit across secondary muscles would need a weighting model the app
    /// doesn't have and can't honestly invent.
    static func volumeByMuscle(_ workouts: [Workout]) -> [MuscleVolume] {
        var totals: [Muscle: Double] = [:]
        for workout in workouts {
            for workoutExercise in workout.exercises ?? [] {
                guard let muscle = workoutExercise.exercise?.primaryMuscle else { continue }
                let volume = (workoutExercise.sets ?? [])
                    .filter(\.isCompleted)
                    .reduce(0) { $0 + $1.setVolumeKg }
                totals[muscle, default: 0] += volume
            }
        }
        return totals
            .map { MuscleVolume(muscle: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    struct ExerciseUsage: Identifiable {
        var id: UUID { exerciseID }
        let exerciseID: UUID
        let name: String
        let sessionCount: Int
        let lastPerformed: Date?
    }

    static func exerciseUsage(_ workouts: [Workout]) -> [ExerciseUsage] {
        var counts: [UUID: (name: String, sessions: Int, last: Date)] = [:]
        for workout in workouts {
            for workoutExercise in workout.exercises ?? [] {
                guard let exercise = workoutExercise.exercise else { continue }
                let hasCompleted = (workoutExercise.sets ?? []).contains(where: \.isCompleted)
                guard hasCompleted else { continue }
                let existing = counts[exercise.id]
                counts[exercise.id] = (
                    exercise.name,
                    (existing?.sessions ?? 0) + 1,
                    max(existing?.last ?? .distantPast, workout.startedAt)
                )
            }
        }
        return counts
            .map { ExerciseUsage(exerciseID: $0.key, name: $0.value.name, sessionCount: $0.value.sessions, lastPerformed: $0.value.last) }
            .sorted { $0.sessionCount > $1.sessionCount }
    }

    /// One bucket per calendar day, for the Profile activity graph (§9.6).
    struct DayBucket: Identifiable {
        var id: Date { date }
        let date: Date
        let durationHours: Double
        let volumeKg: Double
        let reps: Int
    }

    static func dayBuckets(_ workouts: [Workout], calendar: Calendar = .current) -> [DayBucket] {
        let grouped = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.map { day, items in
            DayBucket(
                date: day,
                durationHours: items.reduce(0) { $0 + duration(of: $1) } / 3600,
                volumeKg: items.reduce(0) { $0 + volume(of: $1) },
                reps: items.reduce(0) { $0 + completedSets(in: $1).reduce(0) { $0 + $1.reps } }
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// Above ~3 months a bar per day is unreadable, so buckets collapse to
    /// one per week (§9.6).
    static func aggregateWeekly(_ buckets: [DayBucket], calendar: Calendar = .current) -> [DayBucket] {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let grouped = Dictionary(grouping: buckets) {
            weekCalendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        return grouped.map { week, items in
            DayBucket(
                date: week,
                durationHours: items.reduce(0) { $0 + $1.durationHours },
                volumeKg: items.reduce(0) { $0 + $1.volumeKg },
                reps: items.reduce(0) { $0 + $1.reps }
            )
        }
        .sorted { $0.date < $1.date }
    }
}
