import Foundation
import Observation

/// PRD §6: "You cannot start a second workout while one is live," plus the
/// persistent cross-tab banner. Injected once at the root (`RootTabView`)
/// via `.environment(_:)` so any tab can start/observe/return to the one
/// live workout without threading it through every view's initializer.
@Observable
final class ActiveWorkoutCoordinator {
    var liveWorkout: Workout?
    var isPresented = false

    func present(_ workout: Workout) {
        liveWorkout = workout
        isPresented = true
    }

    func clear() {
        liveWorkout = nil
        isPresented = false
    }
}
