import Foundation
import SwiftData

/// What the home-screen widgets render. Plain values, resolved once in the
/// timeline provider — the widget views never touch SwiftData, for the same
/// reason the Live Activity doesn't (M6 §8): a renderer that can query is a
/// renderer that can disagree with the app.
struct WidgetSnapshot {
    struct Day: Identifiable {
        let id: UUID
        let name: String
        let exerciseCount: Int
        let lastPerformed: Date?
    }

    let splitName: String?
    let days: [Day]
    /// Whether a workout is live right now. The selector becomes a
    /// "resume" prompt instead of offering to start a second one (§6).
    let hasLiveWorkout: Bool
    let liveWorkoutTitle: String?

    let currentStreakWeeks: Int
    let workoutsThisWeek: Int
    let totalWorkouts: Int
    /// Last 5 weeks x 7 days of "did I train", oldest first, for the grid.
    let recentDays: [Bool]

    static let placeholder = WidgetSnapshot(
        splitName: "PPL (Advanced)",
        days: [
            Day(id: UUID(), name: "Mon: Chest & Shoulders", exerciseCount: 4, lastPerformed: nil),
            Day(id: UUID(), name: "Tue: Back & Biceps", exerciseCount: 6, lastPerformed: nil),
            Day(id: UUID(), name: "Thu: Shoulders & Triceps", exerciseCount: 4, lastPerformed: nil),
        ],
        hasLiveWorkout: false,
        liveWorkoutTitle: nil,
        currentStreakWeeks: 3,
        workoutsThisWeek: 2,
        totalWorkouts: 42,
        recentDays: (0..<35).map { $0 % 3 == 0 }
    )
}

/// Reads the shared App Group store. Opens its own container: the widget is a
/// separate process, so it can't reuse the app's instance.
@MainActor
enum WidgetDataSource {
    static func load() -> WidgetSnapshot {
        guard let container = try? ModelContainer(
            for: Schema([
                Exercise.self, RoutineFolder.self, Routine.self, RoutineExercise.self,
                RoutineSetTemplate.self, Workout.self, WorkoutExercise.self, SetLog.self,
                PersonalRecord.self, BodyMetric.self, UserProfile.self, CardioSession.self,
            ]),
            configurations: [ModelConfiguration(url: storeURL())]
        ) else {
            return .placeholder
        }

        let context = ModelContext(container)
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let routines = (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.orderIndex)]))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []

        // Same fallback the Workout tab uses: an explicitly chosen split,
        // else the first folder, so a widget isn't blank for someone who
        // imported a template and never opened the picker.
        let splitName = profile?.activeSplitName.flatMap { $0.isEmpty ? nil : $0 }
            ?? routines.compactMap { $0.folder?.name }.first

        let days = routines
            .filter { splitName == nil ? $0.folder == nil : $0.folder?.name == splitName }
            .prefix(8)
            .map {
                WidgetSnapshot.Day(
                    id: $0.id,
                    name: $0.name,
                    exerciseCount: ($0.exercises ?? []).count,
                    lastPerformed: $0.lastPerformedAt
                )
            }

        let live = workouts.first { $0.endedAt == nil }
        let finished = workouts.filter { $0.endedAt != nil }

        return WidgetSnapshot(
            splitName: splitName,
            days: Array(days),
            hasLiveWorkout: live != nil,
            liveWorkoutTitle: live?.title,
            currentStreakWeeks: ProfileStats.streaks(from: finished).current,
            workoutsThisWeek: workoutsThisWeek(finished),
            totalWorkouts: finished.count,
            recentDays: recentDays(finished)
        )
    }

    private static func workoutsThisWeek(_ workouts: [Workout]) -> Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return workouts.filter { $0.startedAt >= start }.count
    }

    /// 35 days ending today, oldest first.
    private static func recentDays(_ workouts: [Workout]) -> [Bool] {
        let calendar = Calendar.current
        let trained = Set(workouts.map { calendar.startOfDay(for: $0.startedAt) })
        let today = calendar.startOfDay(for: Date())
        return (0..<35).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { trained.contains($0) }
        }
    }

    private static func storeURL() -> URL {
        let filename = "Rerack.sqlite"
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID) {
            return group.appendingPathComponent(filename)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(filename)
    }
}
