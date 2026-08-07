import SwiftUI
import SwiftData

@main
struct RerackApp: App {
    private let container: ModelContainer

    init() {
        let container = ModelContainerFactory.makeContainer()
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
