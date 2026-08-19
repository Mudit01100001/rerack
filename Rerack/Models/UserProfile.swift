import Foundation
import SwiftData

/// PRD §10.1, §10.2. Exactly one row is expected to exist locally in V1 —
/// there's no multi-account concept until V2 introduces sign-in.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var username: String = ""
    var unitPreferenceRaw: String = UnitPreference.kg.rawValue

    /// PRD §10.1: asked in onboarding with a live row preview, reversible
    /// any time in Settings → General → Dominant Hand, same preview.
    var dominantHandRaw: String = DominantHand.right.rawValue

    var defaultRestSeconds: Int = 180

    /// PRD §10.2 Workout section — M5.
    var restTimerSoundEnabled: Bool = true
    /// Build 5 item D: gates the mid-workout "Superset?" nudge
    /// (`ActiveWorkoutView.recordForDetection`) entirely — a defaulted
    /// property, so SwiftData's lightweight migration adds it to existing
    /// rows as `true` with no migration plan needed. Default on because
    /// PRD §7.8.1 frames the prompt as a soft nudge rather than something
    /// the user has to discover a setting to get; off for anyone who finds
    /// the alternation-detection heuristic more annoying than helpful.
    var supersetSuggestionsEnabled: Bool = true
    /// Gates whether ticking a set starts a rest period at all. PRD §7.5 says
    /// there's no manual "start rest" button in V1, so turning this off means
    /// no rest timer runs for the rest of the workout rather than requiring
    /// a manual-start affordance that doesn't exist yet.
    var autoStartRestTimer: Bool = true
    /// PRD §10.2 — applied via `UIApplication.isIdleTimerDisabled`, scoped to
    /// the active workout screen only (`ActiveWorkoutView`), never globally.
    var keepScreenAwakeDuringWorkout: Bool = true

    /// PRD §8.5 / §10.2 — no UI until M6, but the setting exists from M1 so
    /// there's no migration needed when the Live Activity ships.
    var islandTickLogsRaw: String = IslandTickSource.lastSession.rawValue

    /// PRD §10.2 Apple Health / §13.1, default on. Off treats bodyweight
    /// exercises as 0 kg of bodyweight load — "some people prefer this, since
    /// it makes external-load progression easier to read." Only ever consulted
    /// at set-completion time, so flipping it never rewrites past sets.
    var useBodyweightInVolume: Bool = true

    /// The training split currently being followed. Every workout started
    /// from here on snapshots this onto `Workout.splitSnapshot`, so changing
    /// it — which is expected to happen week to week, depending on how hard a
    /// week is going — re-labels future sessions without touching past ones.
    ///
    /// A plain string, not a relationship: a split can be a folder you
    /// imported, one you built, or something you're following out of a book,
    /// and forcing all three through one model would be modelling the app's
    /// convenience rather than the user's reality.
    var activeSplitName: String?

    var hasCompletedOnboarding: Bool = false
    var createdAt: Date = Date()

    init(displayName: String = "", username: String = "") {
        self.displayName = displayName
        self.username = username
    }

    var unitPreference: UnitPreference {
        get { UnitPreference(rawValue: unitPreferenceRaw) ?? .kg }
        set { unitPreferenceRaw = newValue.rawValue }
    }

    var dominantHand: DominantHand {
        get { DominantHand(rawValue: dominantHandRaw) ?? .right }
        set { dominantHandRaw = newValue.rawValue }
    }

    var islandTickLogs: IslandTickSource {
        get { IslandTickSource(rawValue: islandTickLogsRaw) ?? .lastSession }
        set { islandTickLogsRaw = newValue.rawValue }
    }
}
