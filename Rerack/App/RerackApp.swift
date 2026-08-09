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
        }
        .modelContainer(container)
    }
}
