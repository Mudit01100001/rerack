import Foundation
import SwiftData

/// PRD §13.4. Written once per broken record, on workout finish. Ties don't
/// count as new records.
@Model
final class PersonalRecord {
    var id: UUID = UUID()
    var typeRaw: String = PRType.heaviestWeight.rawValue
    var valueKg: Double = 0
    var achievedAt: Date = Date()
    var sourceSetLogID: UUID?
    var sourceWorkoutID: UUID?

    var exercise: Exercise?

    init(type: PRType, valueKg: Double, exercise: Exercise, achievedAt: Date = Date(), sourceSetLogID: UUID? = nil, sourceWorkoutID: UUID? = nil) {
        self.typeRaw = type.rawValue
        self.valueKg = valueKg
        self.exercise = exercise
        self.achievedAt = achievedAt
        self.sourceSetLogID = sourceSetLogID
        self.sourceWorkoutID = sourceWorkoutID
    }

    var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .heaviestWeight }
        set { typeRaw = newValue.rawValue }
    }
}
