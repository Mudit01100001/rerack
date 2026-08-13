import SwiftUI

/// What to load on each side of a bar to hit a target weight.
///
/// Deliberately not automatic: the catalogue's `equipment` field is
/// hand-written (§23.1), so "is this a barbell movement" is a guess, and
/// hiding the calculator on a mislabelled row is worse than offering it on a
/// row that doesn't need one. It lives in every exercise's `···` menu and
/// opens with a sensible bar for that exercise's equipment.
struct PlateCalculatorSheet: View {
    let exerciseName: String
    let equipment: Equipment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.unitPreference) private var unit
    @AppStorage("com.mudit.logbook.plateCalcBarKg") private var barWeightKg = 20.0
    @State private var targetText = ""

    /// Plates are *physical objects*, not a converted number. An imperial
    /// gym racks 45/35/25/10/5/2.5 lb; telling someone in that gym to load
    /// "11.34 kg" is useless. So each unit gets the set that actually exists
    /// on the floor, and the maths runs in kg underneath.
    private var availablePlates: [Double] {
        unit == .kg
            ? [25, 20, 15, 10, 5, 2.5, 1.25]
            : [45, 35, 25, 10, 5, 2.5].map { $0 / Weight.poundsPerKilogram }
    }

    private var barOptions: [(label: String, kg: Double)] {
        unit == .kg
            ? [("Olympic 20 kg", 20), ("Women's 15 kg", 15), ("EZ / curl 10 kg", 10), ("Smith machine 0 kg", 0)]
            : [("Olympic 45 lb", 45 / Weight.poundsPerKilogram),
               ("Women's 35 lb", 35 / Weight.poundsPerKilogram),
               ("EZ / curl 25 lb", 25 / Weight.poundsPerKilogram),
               ("Smith machine 0 lb", 0)]
    }

    /// Typed in whatever unit is showing; converted immediately so the plate
    /// maths below only ever deals in kilograms.
    private var target: Double? {
        guard let kg = Weight.parseToKilograms(targetText, in: unit), kg > 0 else { return nil }
        return kg
    }

    /// Per side. Returns the plates and whatever couldn't be made up — a
    /// remainder is shown rather than silently rounded, because rounding
    /// would tell you to load a weight that isn't the one you asked for.
    private var breakdown: (plates: [(plate: Double, count: Int)], remainderKg: Double)? {
        guard let target else { return nil }
        var perSide = (target - barWeightKg) / 2
        guard perSide >= 0 else { return nil }

        var result: [(Double, Int)] = []
        for plate in availablePlates {
            let count = Int(perSide / plate)
            if count > 0 {
                result.append((plate, count))
                perSide -= Double(count) * plate
            }
        }
        // Floating-point crumbs from repeated subtraction aren't a real
        // remainder — anything under half the smallest plate is zero.
        let smallest = availablePlates.last ?? 1.25
        let remainder = perSide < smallest / 2 ? 0 : perSide
        return (result, remainder)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("0", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(unit.abbreviation).foregroundStyle(.secondary)
                    }
                    Picker("Bar", selection: $barWeightKg) {
                        ForEach(barOptions, id: \.kg) { option in
                            Text(option.label).tag(option.kg)
                        }
                    }
                } footer: {
                    Text(exerciseName)
                }

                Section("Each side") {
                    if let breakdown {
                        if breakdown.plates.isEmpty && breakdown.remainderKg == 0 {
                            Text("Just the bar.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(breakdown.plates, id: \.plate) { entry in
                                HStack {
                                    Text(Weight.format(kg: entry.plate, in: unit, includeUnit: true))
                                        .font(.body.monospacedDigit())
                                    Spacer()
                                    Text("× \(entry.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if breakdown.remainderKg > 0 {
                                HStack {
                                    Text("Can't make up")
                                    Spacer()
                                    Text(Weight.format(kg: breakdown.remainderKg, in: unit, includeUnit: true))
                                        .foregroundStyle(.orange)
                                }
                                .font(.subheadline)
                            }
                        }
                    } else if target != nil {
                        Text("Target is lighter than the bar.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Enter a target weight.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Smith machines carry their own counterweight, so a 20 kg
                // bar assumption would be wrong by exactly one bar.
                if equipment == .smithMachine { barWeightKg = 0 }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
