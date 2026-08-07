import Foundation
import SwiftData

/// PRD §21. Cardio is tracked as its own parallel log, not bolted onto the
/// strength Workout model — the two have almost nothing in common (no sets,
/// no reps, no PR system in V1) and forcing them into one shape would have
/// made both worse.
enum CardioActivity: String, Codable, CaseIterable, Identifiable {
    case treadmill, outdoorRun, bike, outdoorBike, rower, elliptical, swim, walk, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .treadmill: "Treadmill"
        case .outdoorRun: "Outdoor Run"
        case .bike: "Stationary Bike"
        case .outdoorBike: "Outdoor Bike"
        case .rower: "Rowing Machine"
        case .elliptical: "Elliptical"
        case .swim: "Swim"
        case .walk: "Walk"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .treadmill, .outdoorRun, .walk: "figure.run"
        case .bike, .outdoorBike: "figure.outdoor.cycle"
        case .rower: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .swim: "figure.pool.swim"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// A single logged cardio session — manual entry only in V1 (PRD §21).
/// `photoFilename` is a plain visual record of the console; nothing reads
/// numbers out of it yet (that's the on-device OCR research in PRD §22).
@Model
final class CardioSession {
    var id: UUID = UUID()
    var activityRaw: String = CardioActivity.treadmill.rawValue
    var startedAt: Date = Date()
    var durationSec: Int = 0
    var distanceMeters: Double?
    var caloriesKcal: Double?

    /// Only meaningful for `.treadmill`.
    var inclinePercent: Double?
    /// Only meaningful for `.bike`, `.rower`, `.elliptical`.
    var resistanceLevel: Double?

    var notes: String?
    var photoFilename: String?

    /// Reserved for when HealthKit cardio write ships (PRD §21) — not yet
    /// wired up, so this is always false in V1.
    var syncedToHealthKit: Bool = false

    var createdAt: Date = Date()

    init(activity: CardioActivity, startedAt: Date = Date(), durationSec: Int = 0) {
        self.activityRaw = activity.rawValue
        self.startedAt = startedAt
        self.durationSec = durationSec
    }

    var activity: CardioActivity {
        get { CardioActivity(rawValue: activityRaw) ?? .other }
        set { activityRaw = newValue.rawValue }
    }
}
