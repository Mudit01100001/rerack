import SwiftUI

/// PRD §7.2/§7.3/§7.9. `existingSet == nil` means this row is still a ghost
/// (or, for a drop row, an uncommitted pending drop) — pure view state,
/// nothing in the database yet. Ticking commits it; ticking an existing row
/// is the un-tick path (revert to editable).
struct SetRowView: View {
    let orderIndex: Int
    let existingSet: SetLog?
    let ghost: GhostSet?
    /// §7.9: renders indented with a "D" label and connector instead of the
    /// numeric set index.
    var isDrop: Bool = false
    /// §7.9: the −20%-of-parent pre-fill for an uncommitted drop row. Plays
    /// the same "grey until edited or ticked" role `ghost` plays for a
    /// normal row — `showsAsGhost` below treats the two identically.
    var dropPrefillWeightKg: Double? = nil
    let onComplete: (_ weightKg: Double, _ reps: Int) -> Void
    let onUncomplete: () -> Void
    let onDeleteExisting: () -> Void
    /// nil hides the "+ Drop" swipe action — callers only pass a closure for
    /// a completed row (PRD §15: blocked on an incomplete parent).
    var onAddDrop: (() -> Void)? = nil

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var hasEdited = false

    private var isCompleted: Bool { existingSet?.isCompleted == true }

    /// PRD §4 Principle 5: grey means suggestion, black means fact — with no
    /// exceptions. This is the one flag that decides which it is.
    ///
    /// An *un-ticked* `existingSet` counts as a suggestion too. Since M6 §9.3
    /// a drop row exists in the database from the moment it's added, so row
    /// existence no longer implies "this happened" — only `isCompleted` does.
    private var showsAsGhost: Bool {
        guard !isCompleted, !hasEdited else { return false }
        return ghost != nil || dropPrefillWeightKg != nil || existingSet != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            // §7.9: drop rows are indented and tethered to the parent with a
            // small connector glyph, marked "D" instead of a set number.
            Group {
                if isDrop {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                } else {
                    Text("\(orderIndex + 1)")
                        .font(.subheadline)
                }
            }
            .frame(width: 20)
            .foregroundStyle(.secondary)
            .padding(.leading, isDrop ? 16 : 0)

            if isDrop {
                Text("D")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

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
            // PRD §7.9/§7.4: offered only on a completed row — the caller
            // withholds `onAddDrop` entirely for anything not yet ticked
            // (§15 "drop set added to an incomplete parent" is blocked).
            if let onAddDrop {
                Button(action: onAddDrop) {
                    Label("+ Drop", systemImage: "arrow.turn.down.right")
                }
                .tint(.orange)
            }
        }
        .onAppear(perform: populate)
        .onChange(of: existingSet?.id) { _, _ in populate() }
        .onChange(of: existingSet?.isCompleted) { _, _ in populate() }
    }

    private func populate() {
        if let existingSet {
            weightText = formatted(existingSet.addedWeightKg)
            // §7.9: reps genuinely vary set-to-set on a drop, so an un-ticked
            // drop added by hand carries `reps == 0` as "not guessed yet"
            // rather than a fact-shaped lie (Principle 5). A reproduced chain
            // does carry last session's reps, and shows them.
            repsText = (!existingSet.isCompleted && existingSet.reps == 0) ? "" : String(existingSet.reps)
            hasEdited = existingSet.isCompleted
        } else if let ghost {
            weightText = formatted(ghost.weightKg)
            repsText = String(ghost.reps)
            hasEdited = false
        } else if let dropPrefillWeightKg {
            // §7.9: only the weight is pre-filled — reps genuinely vary
            // set-to-set on a drop, so guessing one would be a fact-shaped
            // lie (PRD §4 Principle 5).
            weightText = formatted(dropPrefillWeightKg)
            repsText = ""
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
