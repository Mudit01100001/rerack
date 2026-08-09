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
        .modifier(LiveWorkoutAccessory(coordinator: coordinator))
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
                    },
                    // Only dismisses the cover. The workout stays live and
                    // the banner reappears, so nothing is lost.
                    onMinimize: { coordinator.isPresented = false }
                )
            }
        }
        .task {
            recoverLiveWorkoutIfAny()
        }
        // M6 §6.3: every Live Activity surface deep-links here. All three
        // URLs (`active`, `?focus=…`, `?finish=1`) land on the active-workout
        // screen; the focus/finish refinements are handled by the screen the
        // user is now looking at, which is already the right one.
        .onOpenURL { url in
            guard url.scheme == WorkoutDeepLink.scheme else { return }
            recoverLiveWorkoutIfAny()
            if coordinator.liveWorkout != nil {
                coordinator.isPresented = true
            }
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

/// Parks the live-workout pill against the tab bar.
///
/// iOS 26 has an API for exactly this shape (the slot Apple Music's
/// now-playing bar sits in), and it docks the pill *above* the tab bar
/// instead of over it. `.safeAreaInset` doesn't: with the floating tab bar it
/// lays the pill inside the content area, where it covered the tab labels.
/// Older versions keep the inset and add clearance by hand.
private struct LiveWorkoutAccessory: ViewModifier {
    let coordinator: ActiveWorkoutCoordinator

    private var isShowing: Bool {
        coordinator.liveWorkout != nil && !coordinator.isPresented
    }

    func body(content: Content) -> some View {
        // The branch has to be on whether the modifier is applied *at all*,
        // not on what it returns. `tabViewBottomAccessory` reserves and draws
        // its container as soon as it's attached, so returning an empty view
        // from inside it left a permanent blank pill docked above the tab bar
        // with no workout running.
        if isShowing {
            if #available(iOS 26.0, *) {
                content.tabViewBottomAccessory {
                    ActiveWorkoutBanner(coordinator: coordinator)
                }
            } else {
                content.safeAreaInset(edge: .bottom) {
                    ActiveWorkoutBanner(coordinator: coordinator)
                        // Clears the floating tab bar, which the inset
                        // otherwise lets the pill sit on top of.
                        .padding(.horizontal, DS.Space.md)
                        .padding(.bottom, DS.Space.xl + DS.Space.lg)
                }
            }
        } else {
            content
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Exercise.self, Routine.self, Workout.self], inMemory: true)
}
