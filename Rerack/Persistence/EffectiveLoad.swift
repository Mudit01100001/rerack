import Foundation

/// PRD §13.1. The one place `effective_load = (bodyweight × bodyweight_factor)
/// + added_weight` is computed. Callers snapshot the result into
/// `SetLog.effectiveLoadKg` and never recompute it — a later change in
/// bodyweight must not silently rewrite historical volume.
enum EffectiveLoad {
    /// `bodyweightKg` is the workout's snapshot (`Workout.bodyweightKg`),
    /// which is `nil` when Health is unavailable, was declined, or holds no
    /// bodyweight sample. In that case bodyweight simply contributes nothing
    /// — a bodyweight exercise logs its added weight only, which is exactly
    /// what the app did before M9 and what §10.2's "Use bodyweight in volume
    /// maths" toggle produces when it's switched off.
    static func kg(
        addedWeightKg: Double,
        loadType: LoadType,
        bodyweightFactor: Double,
        bodyweightKg: Double?,
        useBodyweightInVolume: Bool
    ) -> Double {
        guard useBodyweightInVolume, let bodyweightKg else { return addedWeightKg }
        switch loadType {
        case .external:
            // Factor is meaningless here and stored as 0 anyway (§9.1) —
            // returning early keeps a bad catalogue row from leaking
            // bodyweight into a barbell lift.
            return addedWeightKg
        case .bodyweight, .weightedBodyweight:
            return bodyweightKg * bodyweightFactor + addedWeightKg
        case .assisted:
            // §13.1: assistance is logged as a negative `addedWeightKg`, so
            // the same sum already subtracts it — an assisted pull-up at
            // −30 kg with a 74 kg bodyweight is 44 kg of effective load.
            return bodyweightKg * bodyweightFactor + addedWeightKg
        }
    }
}
