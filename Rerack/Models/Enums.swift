import Foundation

// MARK: - Exercise taxonomy (PRD §9.1)

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, smithMachine, bodyweight
    case kettlebell, band, plate, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .smithMachine: "Smith Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .plate: "Plate"
        case .other: "Other"
        }
    }
}

enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest
    case backLats, backUpper
    case shouldersFront, shouldersSide, shouldersRear
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case abs, obliques, lowerBack
    case neck, fullBody

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .backLats: "Back (Lats)"
        case .backUpper: "Back (Upper/Traps)"
        case .shouldersFront: "Shoulders (Front)"
        case .shouldersSide: "Shoulders (Side)"
        case .shouldersRear: "Shoulders (Rear)"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .lowerBack: "Lower Back"
        case .neck: "Neck"
        case .fullBody: "Full Body"
        }
    }
}

/// Drives the bodyweight-in-volume maths in PRD §13.1.
enum LoadType: String, Codable, CaseIterable, Identifiable {
    /// Fully externally loaded — barbell, dumbbell, machine, cable, etc. Bodyweight
    /// never enters the volume calculation.
    case external
    /// Bodyweight is the load. `Exercise.bodyweightFactor` scales how much of it counts
    /// (pull-up = 1.0, push-up = 0.64, inverted row = 0.5).
    case bodyweight
    /// Bodyweight plus added weight (a weighted pull-up belt, a weighted dip).
    case weightedBodyweight
    /// Bodyweight minus machine assistance — added weight is logged as a negative.
    case assisted

    var id: String { rawValue }
}

// MARK: - Sets (PRD §7.2, §7.8, §7.9)

enum SetType: String, Codable, CaseIterable, Identifiable {
    case normal, warmup, drop, failure

    var id: String { rawValue }

    /// What's shown in the Set # column (PRD §7.2).
    var shortLabel: String {
        switch self {
        case .normal: ""
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }
}

/// PRD §17: distinguishes a set completed in-app from one ticked off the
/// Live Activity / Dynamic Island (M6). Stored locally, exported, never
/// transmitted — and per §17, the single most interesting number in the
/// product once M6 ships.
enum LoggedFrom: String, Codable {
    case app
    case liveActivity = "live_activity"
}

// MARK: - Personal records (PRD §13.4)

enum PRType: String, Codable, CaseIterable {
    case heaviestWeight, best1RM, bestSetVolume, bestSessionVolume
}

/// Bitmask backing `SetLog.prFlagsRaw` so a single set can carry more than
/// one broken record (e.g. heaviest weight AND best set volume in the same set).
struct PRFlags: OptionSet, Codable {
    let rawValue: Int
    static let heaviestWeight = PRFlags(rawValue: 1 << 0)
    static let best1RM = PRFlags(rawValue: 1 << 1)
    static let bestSetVolume = PRFlags(rawValue: 1 << 2)
    static let bestSessionVolume = PRFlags(rawValue: 1 << 3)
}

// MARK: - Body metrics (PRD §9.7)

enum MetricType: String, Codable, CaseIterable {
    case bodyweight, bodyFatPercentage
}

enum MetricSource: String, Codable {
    case healthKit, manual
}

// MARK: - User profile (PRD §10.1, §10.2)

enum DominantHand: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var displayName: String { self == .right ? "Right" : "Left" }
}

enum UnitPreference: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var displayName: String { self == .kg ? "Kilograms (kg)" : "Pounds (lb)" }
}

/// PRD §8.5 / §10.2 — what a tick on the Live Activity logs when the values
/// shown haven't been edited. Schema exists from M1; the setting has no UI
/// until M6.
enum IslandTickSource: String, Codable, CaseIterable {
    case lastSession, routineTarget
}
