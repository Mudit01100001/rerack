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

    /// PRD §8.5 / §10.2 — no UI until M6, but the setting exists from M1 so
    /// there's no migration needed when the Live Activity ships.
    var islandTickLogsRaw: String = IslandTickSource.lastSession.rawValue

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
