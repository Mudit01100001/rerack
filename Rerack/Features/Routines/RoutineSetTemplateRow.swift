import SwiftUI

/// PRD §9.3: one target set within a routine exercise — the values that seed
/// ghost sets the first time the routine is ever run (§7.3).
struct RoutineSetTemplateRow: View {
    @Environment(\.unitPreference) private var unit
    @Bindable var template: RoutineSetTemplate
    let onDelete: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SetType.allCases) { type in
                    Button(label(for: type)) { template.setType = type }
                }
            } label: {
                Text(menuLabel)
                    .font(.caption)
                    .frame(width: 52, alignment: .leading)
            }

            TextField(unit.abbreviation, text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: weightText) { _, newValue in
                    // Stored in kg regardless of what's on screen, so a
                    // template built in pounds still seeds ghost sets
                    // correctly for someone reading kilograms.
                    template.targetWeightKg = Weight.parseToKilograms(newValue, in: unit)
                }

            Text("×")
                .foregroundStyle(.secondary)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: repsText) { _, newValue in
                    template.targetReps = Int(newValue)
                }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            weightText = template.targetWeightKg.map { Weight.format(kg: $0, in: unit) } ?? ""
            repsText = template.targetReps.map(String.init) ?? ""
        }
    }

    private var menuLabel: String {
        template.setType == .normal ? "Set" : template.setType.shortLabel
    }

    private func label(for type: SetType) -> String {
        switch type {
        case .normal: "Normal"
        case .warmup: "Warm-up"
        case .drop: "Drop"
        case .failure: "Failure"
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }
}
