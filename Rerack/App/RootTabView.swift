import SwiftUI

/// PRD §6: four tabs — Home, Workout, Cardio, Profile — nothing else at root level.
/// (Cardio added post-M1; strength and cardio are tracked as separate,
/// parallel logs rather than cardio being buried inside Workout.)
struct RootTabView: View {
    @AppStorage(AppearanceStorageKey.value) private var appearanceModeRaw = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            WorkoutTabView()
                .tabItem { Label("Workout", systemImage: "dumbbell") }

            CardioTabView()
                .tabItem { Label("Cardio", systemImage: "figure.run") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Exercise.self, Routine.self, Workout.self], inMemory: true)
}
