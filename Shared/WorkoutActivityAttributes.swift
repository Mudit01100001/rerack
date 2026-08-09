import Foundation
import ActivityKit

/// PRD §8 / M6 §8. Compiled into **both** the app and the widget extension —
/// it's the only type they share, and it deliberately carries no SwiftData,
/// no `GhostSetResolver`, and no formatting logic.
///
/// Everything textual is pre-composed in the app (M6 §8): one implementation
/// of the wording, one place to fix it, and the widget stays a dumb renderer
/// that can't disagree with the app about what a set is called.
struct WorkoutActivityAttributes: ActivityAttributes {
    /// Frozen at start — nothing in the app edits a workout's title mid-session.
    let workoutID: UUID
    let workoutTitle: String
    /// Drives the elapsed-time counter, which ticks on-device from this
    /// instant rather than costing an update push per second (§P3).
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        /// M6 §7: the entire phase enum. "Ready", "Finished" and "All done"
        /// are deliberately not phases — see M6 §11 items 2 and 4.
        enum Phase: String, Codable, Hashable {
            case logging, resting
        }

        /// M6 §5.3. The payload the tick will write, byte for byte.
        enum Payload: Codable, Hashable {
            case known(weightKg: Double, reps: Int)
            /// Reps known, weight genuinely absent — only valid for
            /// `loadType == .bodyweight`, where writing 0 kg is correct
            /// (§7.2 allows it, §13.1 makes it mean something).
            case repsOnly(reps: Int)
            /// No honest values to show, so no tick is rendered at all.
            case unknown
        }

        var phase: Phase
        /// Absolute instant, non-nil iff resting. Drives
        /// `Text(timerInterval:)`, which counts down on-device with zero
        /// update pushes (M6 §P3).
        var restEndsAt: Date?
        /// The other end of the rest range — a determinate progress bar needs
        /// both, unlike the countdown which only needs the end.
        var restStartedAt: Date?

        /// Asset-catalogue name for this exercise's thumbnail, or nil while
        /// no artwork exists for it. Carried end-to-end now so dropping real
        /// images in later is an asset-catalogue change and nothing more.
        var exerciseImageName: String?

        /// Intent target and deep-link focus. Nil ⇒ nothing planned remains.
        var workoutExerciseID: UUID?
        var setIndex: Int
        var exerciseName: String?
        var supersetLabel: String?
        var positionLabel: String
        var compactToken: String
        var payload: Payload
        /// Pre-composed; nil ⇒ the line is absent. M6 §5.1: it appears only
        /// when the pointer's next step changes exercise, which makes its
        /// mere presence the superset signal.
        var thenLine: String?

        static var allLogged: ContentState {
            ContentState(
                phase: .logging,
                restEndsAt: nil,
                restStartedAt: nil,
                exerciseImageName: nil,
                workoutExerciseID: nil,
                setIndex: 0,
                exerciseName: nil,
                supersetLabel: nil,
                positionLabel: "",
                compactToken: "✓",
                payload: .unknown,
                thenLine: nil
            )
        }
    }
}

/// M6 §6.3. Kept next to the attributes so the app's URL handler and the
/// widget's links can't drift apart.
enum WorkoutDeepLink {
    static let scheme = "rerack"

    static var active: URL { URL(string: "\(scheme)://workout/active")! }

    static func focus(workoutExerciseID: UUID, setIndex: Int) -> URL {
        URL(string: "\(scheme)://workout/active?focus=\(workoutExerciseID.uuidString)&set=\(setIndex)&field=weight")!
    }

    static var finish: URL { URL(string: "\(scheme)://workout/active?finish=1")! }
}
