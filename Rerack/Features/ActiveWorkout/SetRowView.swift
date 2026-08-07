import SwiftUI

/// PRD §7.2/§7.3. `existingSet == nil` means this row is still a ghost —
/// pure view state, nothing in the database yet. Ticking a ghost row commits
/// it; ticking an existing one is the un-tick path (revert to editable).
struct SetRowView: View {
    let orderIndex: Int
    let existingSet: SetLog?
    let ghost: GhostSet?
    let onComplete: (_ weightKg: Double, _ reps: Int) -> Void
    let onUncomplete: () -> Void
    let onDeleteExisting: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var hasEdited = false

    private var isCompleted: Bool { existingSet?.isCompleted == true }

    /// PRD §4 Principle 5: grey means suggestion, black means fact — with no
    /// exceptions. This is the one flag that decides which it is.
    private var showsAsGhost: Bool { !isCompleted && !hasEdited && ghost != nil }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(orderIndex + 1)")
                .font(.subheadline)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Group {
                if let ghost {
                    Text("\(formatted(ghost.weightKg)) × \(ghost.reps)")
                } else {
                    Text("—")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 60, alignment: .leading)

            TextField("kg", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .foregroundStyle(showsAsGhost ? .secondary : .primary)
                .onChange(of: weightText) { _, _ in hasEdited = true }

            Text("×").foregroundStyle(.secondary)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .foregroundStyle(showsAsGhost ? .secondary : .primary)
                .onChange(of: repsText) { _, _ in hasEdited = true }

            Spacer(minLength: 4)

            Button(action: toggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing) {
            if existingSet != nil {
                Button(role: .destructive, action: onDeleteExisting) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onAppear(perform: populate)
        .onChange(of: existingSet?.id) { _, _ in populate() }
        .onChange(of: existingSet?.isCompleted) { _, _ in populate() }
    }

    private func populate() {
        if let existingSet {
            weightText = formatted(existingSet.addedWeightKg)
            repsText = String(existingSet.reps)
            hasEdited = true
        } else if let ghost {
            weightText = formatted(ghost.weightKg)
            repsText = String(ghost.reps)
            hasEdited = false
        } else {
            weightText = ""
            repsText = ""
            hasEdited = false
        }
    }

    private func toggle() {
        if isCompleted {
            onUncomplete()
        } else {
            // PRD §7.2: empty reps blocks completion; 0 kg is allowed
            // (bodyweight exercises, §13.1).
            guard let reps = Int(repsText), reps > 0 else { return }
            let weight = Double(weightText) ?? 0
            onComplete(weight, reps)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
