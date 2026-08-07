import Foundation
import SwiftData

/// PRD §12.2. Builds the one SwiftData container the whole app runs on.
enum ModelContainerFactory {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            RoutineFolder.self,
            Routine.self,
            RoutineExercise.self,
            RoutineSetTemplate.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            PersonalRecord.self,
            BodyMetric.self,
            UserProfile.self,
            CardioSession.self,
        ])

        let configuration = ModelConfiguration(schema: schema, url: storeURL())

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    /// Puts the store inside the shared App Group container rather than the
    /// app's private sandbox, so the widget extension a future Live Activity
    /// (PRD §8, M6) ships in can read the same database with zero migration —
    /// retrofitting this after the fact is the painful path §12.2 calls out.
    ///
    /// Falls back to the app's own Application Support directory if the App
    /// Group entitlement isn't resolvable on this build (e.g. running under
    /// a signing configuration where the group hasn't been provisioned yet),
    /// so the app still runs standalone rather than crashing on launch.
    private static func storeURL() -> URL {
        let filename = "Rerack.sqlite"

        if let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID
        ) {
            return groupContainer.appendingPathComponent(filename)
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(filename)
    }
}
