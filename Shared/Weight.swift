import SwiftUI

/// PRD §10.2 "Units". One place that converts and formats weight.
///
/// Lives in `Shared/` because `WorkoutEngine` compiles into the widget
/// extension as well as the app, and the Live Activity's payload wording goes
/// through here — one implementation of "20 kg × 5", not two that can drift.
///
/// **Kilograms remain the storage unit, everywhere, permanently.** Every
/// `…Kg` property on a model, every `_kg` CSV column, and the HealthKit
/// bridge all stay metric. Only what's drawn on screen and what's typed into
/// a field passes through here.
///
/// That split is not a stylistic preference. History is stored as a number,
/// and if the stored number changed meaning when a setting flipped, every
/// past workout would silently rewrite itself — the same failure
/// `SetLog.effectiveLoadKg` is snapshotted to avoid (§13.1). It would also
/// break every spreadsheet already built against an exported `_kg` column.
enum Weight {
    /// Exact by definition: 1 lb = 0.45359237 kg.
    static let poundsPerKilogram = 2.20462262184878

    // MARK: - Conversion

    static func toDisplay(kg: Double, in unit: UnitPreference) -> Double {
        unit == .kg ? kg : kg * poundsPerKilogram
    }

    static func toKilograms(display value: Double, in unit: UnitPreference) -> Double {
        unit == .kg ? value : value / poundsPerKilogram
    }

    // MARK: - Formatting

    /// `20`, `22.5`, `2.25`. Trailing zeroes are dropped because a set row is
    /// a dense grid of numbers and `20.00 kg` costs width for nothing.
    ///
    /// Pounds get one decimal at most: converted kilos land on values like
    /// `44.0924`, and presenting that many digits implies a precision the
    /// original 20 kg never had.
    static func format(kg: Double, in unit: UnitPreference, includeUnit: Bool = false) -> String {
        let value = toDisplay(kg: kg, in: unit)
        let rounded = unit == .kg
            ? (value * 100).rounded() / 100
            : (value * 10).rounded() / 10
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(format: unit == .kg ? "%.2f" : "%.1f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return includeUnit ? "\(text) \(unit.abbreviation)" : text
    }

    /// Whole-number totals: session volume, lifetime volume, card figures.
    /// Grouped so `48,200` doesn't read as a phone number.
    static func formatTotal(kg: Double, in unit: UnitPreference, includeUnit: Bool = true) -> String {
        let value = Int(toDisplay(kg: kg, in: unit).rounded())
        let text = value.formatted()
        return includeUnit ? "\(text) \(unit.abbreviation)" : text
    }

    /// What a user typed, back into storage. Empty or unparseable is nil
    /// rather than 0 — "I didn't fill this in" and "zero kilos" are different
    /// answers, and §7.2 allows a genuine 0 for bodyweight movements.
    static func parseToKilograms(_ text: String, in unit: UnitPreference) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned) else { return nil }
        return toKilograms(display: value, in: unit)
    }

    // MARK: - Increments

    /// The smallest step that exists in a real gym, per unit. Used for
    /// rounding suggestions (drop sets, §7.9) so a proposal is a weight you
    /// can actually load rather than 17.6 kg.
    static func increment(for unit: UnitPreference) -> Double {
        // 2.5 kg is the usual smallest pair of plates; 5 lb is its imperial
        // equivalent, not 2.5 lb, because 1.25 lb plates are rare.
        unit == .kg ? 2.5 : 5 / poundsPerKilogram
    }
}

extension UnitPreference {
    var abbreviation: String { self == .kg ? "kg" : "lb" }
}

// MARK: - Environment

/// Read from the environment rather than queried per view: weights render in
/// dozens of rows per screen, and onboarding needs to preview a choice that
/// hasn't been saved yet — the same reasoning as `\.dominantHand`.
private struct UnitPreferenceKey: EnvironmentKey {
    static let defaultValue: UnitPreference = .kg
}

extension EnvironmentValues {
    var unitPreference: UnitPreference {
        get { self[UnitPreferenceKey.self] }
        set { self[UnitPreferenceKey.self] = newValue }
    }
}
