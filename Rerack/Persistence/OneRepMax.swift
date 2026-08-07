import Foundation

/// PRD §13.3. Epley formula: `weight × (1 + reps / 30)`, `= weight` at
/// `reps == 1`. Returns `nil` — never a number — for reps > 12 and for drop
/// sets (§7.9: "a fatigued drop set produces a meaningless estimate"). This
/// is the one place that decision is made, so `PersonalRecordDetector`'s
/// Best 1RM check gets drop-exclusion for free by going through here.
enum OneRepMax {
    static func estimate(weightKg: Double, reps: Int, setType: SetType) -> Double? {
        guard setType != .drop else { return nil }
        guard reps >= 1, reps <= 12 else { return nil }
        guard reps > 1 else { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}
