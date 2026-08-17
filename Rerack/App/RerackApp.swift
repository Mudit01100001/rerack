import SwiftUI
import SwiftData

@main
struct RerackApp: App {
    private let container: ModelContainer

    init() {
        // The shared instance, not a fresh one — a Live Activity intent
        // performing in this same process must see the same container (M6 §P7).
        let container = ModelContainerFactory.shared
        self.container = container
        ExerciseSeeder.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // A cold Taptic Engine lands the first tap of a session
                    // tens of milliseconds late, which made the very first
                    // set of a workout feel unresponsive while every later
                    // one felt fine.
                    Haptics.warmUp()
                }
        }
        .modelContainer(container)
    }
}
