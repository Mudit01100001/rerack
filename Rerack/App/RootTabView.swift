import SwiftUI
import SwiftData
import WidgetKit

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
    @State private var showingOnboarding = false
    @Query private var profiles: [UserProfile]

    /// Shown when no profile has completed it. A profile row can be created
    /// by other screens before onboarding ever runs (Settings does it
    /// lazily), so the flag on the row is the source of truth rather than
    /// "does a profile exist".
    /// Read once here so the value used for the tab hierarchy and the value
    /// re-injected into presented covers can't disagree.
    private var dominantHand: DominantHand {
        profiles.first?.dominantHand ?? .right
    }

    private func decideOnboarding() {
        showingOnboarding = !(profiles.first?.hasCompletedOnboarding ?? false)
    }

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
        .environment(\.dominantHand, dominantHand)
        .preferredColorScheme(appearanceMode.colorScheme)
        .modifier(LiveWorkoutAccessory(coordinator: coordinator))
        // §10.1: shown once, before anything else. `fullScreenCover` rather
        // than a sheet — it isn't dismissible by dragging, and a half-swiped
        // first run that lands you in an empty app is a bad first impression.
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView { showingOnboarding = false }
        }
        .task { decideOnboarding() }
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
                // Re-injected rather than inherited. A presented cover does
                // not reliably carry custom environment keys across the
                // presentation boundary, so the tick stayed right-handed on
                // the one screen the setting exists for.
                .environment(\.dominantHand, dominantHand)
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

            // A widget tap naming a specific workout starts it — but never
            // over a live one (§6). If something's already running, the tap
            // resolves to "take me back to it" instead, which is what the
            // widget was showing anyway.
            if let routineID = WorkoutDeepLink.routineID(from: url), coordinator.liveWorkout == nil {
                startRoutine(id: routineID)
            }
            if coordinator.liveWorkout != nil {
                coordinator.isPresented = true
            }
        }
    }

    /// PRD §7.7: "if a Workout exists with endedAt == nil, the app restores
    /// it and returns to the active workout screen." The 12-hour
    /// abandoned-workout prompt is a fast-follow, not built here.
    /// Starts a routine named by a widget deep link. Silently does nothing if
    /// the routine was deleted since the widget last refreshed, or has no
    /// exercises — the same guards `RoutineListView.start` applies, since a
    /// widget tap shouldn't be able to create a workout the app itself
    /// wouldn't.
    private func startRoutine(id: UUID) {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })
        guard let routine = try? modelContext.fetch(descriptor).first,
              !(routine.exercises ?? []).isEmpty
        else { return }
        let workout = WorkoutStarter.start(routine: routine, context: modelContext)
        routine.lastPerformedAt = Date()
        try? modelContext.save()
        coordinator.present(workout)
        // The selector switches to "in progress" the moment one starts.
        WidgetCenter.shared.reloadAllTimelines()
    }

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
