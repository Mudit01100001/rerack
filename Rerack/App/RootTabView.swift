import SwiftUI
import SwiftData

/// PRD §6: four tabs — Home, Workout, Cardio, Profile — nothing else at root level.
/// (Cardio added post-M1; strength and cardio are tracked as separate,
/// parallel logs rather than cardio being buried inside Workout.)
///
/// Also owns the one `ActiveWorkoutCoordinator` for the whole app (PRD §6:
/// "You cannot start a second workout while one is live," plus the
/// persistent cross-tab banner and crash-recovery-on-launch, §7.7).
struct RootTabView: View {
    @AppStorage(AppearanceStorageKey.value) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = ActiveWorkoutCoordinator()

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
        .environment(coordinator)
        .preferredColorScheme(appearanceMode.colorScheme)
        .safeAreaInset(edge: .bottom) {
            if coordinator.liveWorkout != nil && !coordinator.isPresented {
                ActiveWorkoutBanner(coordinator: coordinator)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { coordinator.isPresented },
                set: { coordinator.isPresented = $0 }
            )
        ) {
            if let workout = coordinator.liveWorkout {
                ActiveWorkoutView(
                    workout: workout,
                    onFinish: { coordinator.clear() },
                    onDiscard: {
                        modelContext.delete(workout)
                        coordinator.clear()
                    }
                )
            }
        }
        .task {
            recoverLiveWorkoutIfAny()
        }
    }

    /// PRD §7.7: "if a Workout exists with endedAt == nil, the app restores
    /// it and returns to the active workout screen." The 12-hour
    /// abandoned-workout prompt is a fast-follow, not built here.
    private func recoverLiveWorkoutIfAny() {
        guard coordinator.liveWorkout == nil else { return }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil })
        if let live = try? modelContext.fetch(descriptor).first {
            coordinator.present(live)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Exercise.self, Routine.self, Workout.self], inMemory: true)
}
