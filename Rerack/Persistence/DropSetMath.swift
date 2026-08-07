import Foundation

/// PRD §7.9: the pre-fill shown when a drop row is added — a starting
/// suggestion, not a lock. The row is still editable up until it's ticked.
enum DropSetMath {
    static func prefillWeightKg(fromParent parentWeightKg: Double, roundingToKg increment: Double = 2.5) -> Double {
        let target = parentWeightKg * 0.8
        return (target / increment).rounded() * increment
    }
}
