import Foundation
import SwiftData

/// PRD §9.7. Bodyweight and body-fat readings, sourced from Apple Health or
/// entered manually as a fallback. Feeds the Measures dashboard (M9) and the
/// bodyweight-in-volume maths (§13.1).
@Model
final class BodyMetric {
    var id: UUID = UUID()
    var typeRaw: String = MetricType.bodyweight.rawValue
    var value: Double = 0
    var date: Date = Date()
    var sourceRaw: String = MetricSource.manual.rawValue

    init(type: MetricType, value: Double, date: Date = Date(), source: MetricSource = .manual) {
        self.typeRaw = type.rawValue
        self.value = value
        self.date = date
        self.sourceRaw = source.rawValue
    }

    var type: MetricType {
        get { MetricType(rawValue: typeRaw) ?? .bodyweight }
        set { typeRaw = newValue.rawValue }
    }

    var source: MetricSource {
        get { MetricSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
