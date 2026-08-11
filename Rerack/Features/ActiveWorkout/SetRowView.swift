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

    @Environment(\.dominantHand) private var dominantHand

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

    /// Column widths are shared with `ExerciseCardView.columnHeaders` — the
    /// header row and every set row read from the same numbers, so they can't
    /// drift out of alignment.
    /// §10.1: the tick moves to the leading edge for a left-handed user, so
    /// the thumb that reaches it isn't crossing the row over the numbers it
    /// just entered. Everything else keeps its order.
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if dominantHand == .left {
                tickButton
            }
            rowContent
            if dominantHand == .right {
                tickButton
            }
        }
        .onAppear(perform: populate)
        .onChange(of: existingSet?.id) { _, _ in populate() }
        .onChange(of: existingSet?.isCompleted) { _, _ in populate() }
    }

    private var tickButton: some View {
        Button(action: toggle) {
            // §17: never colour alone. The glyph *fills* when complete, so
            // state survives greyscale and every form of colour blindness.
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .dsFont(DS.TypeScale.heading, relativeTo: .title3)
                .foregroundStyle(isCompleted ? Color.green : Color.secondary.opacity(0.6))
                // §17 requires >= 44x44pt. The glyph is ~22pt; the frame here
                // is the hit area, and it's the most-tapped control in the
                // app, so it gets the full target even though the column is
                // drawn narrower.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 30)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(isCompleted ? "Double tap to un-log" : "Double tap to log")
        .accessibilityAddTraits(isCompleted ? [.isButton, .isSelected] : .isButton)
    }

    /// One spoken sentence per row. VoiceOver reading "1", "20 by 5", "20",
    /// "5", "circle" as five separate elements is technically labelled and
    /// practically useless mid-set, so the tick carries the whole row.
    private var accessibilitySummary: String {
        let position = isDrop ? "Drop set" : "Set \(orderIndex + 1)"
        let weight = weightText.isEmpty ? "no weight" : "\(weightText) kilograms"
        let reps = repsText.isEmpty ? "no reps" : "\(repsText) reps"
        let state = isCompleted ? "completed" : "not logged"
        return "\(position), \(weight), \(reps), \(state)"
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: DS.Space.xs) {
            // §7.9: drop rows are indented and marked "D" instead of a number.
            Group {
                if isDrop {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.turn.down.right")
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        Text("D")
                            .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .bold)
                    }
                } else {
                    Text("\(orderIndex + 1)")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                }
            }
            .frame(width: 26, alignment: .leading)
            .foregroundStyle(.secondary)

            Group {
                if let ghost {
                    Text("\(formatted(ghost.weightKg))×\(ghost.reps)")
                } else {
                    Text("-")
                }
            }
            .dsFont(DS.TypeScale.caption, relativeTo: .caption, design: .rounded)
            .foregroundStyle(.tertiary)
            .frame(width: 66, alignment: .leading)

            entryField(text: $weightText, placeholder: "kg", width: 58, keyboard: .decimalPad)
            entryField(text: $repsText, placeholder: "reps", width: 48, keyboard: .numberPad)

            Spacer(minLength: 0)
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
    }

    /// Editable fields carry a filled background and a border; static text
    /// doesn't. That's the app-wide rule now — if you can change it, it looks
    /// like a control.
    private func entryField(
        text: Binding<String>,
        placeholder: String,
        width: CGFloat,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .medium, design: .rounded)
            .foregroundStyle(showsAsGhost ? .secondary : .primary)
            .frame(width: width, height: 34)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: .rect(cornerRadius: DS.Radius.small, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .onChange(of: text.wrappedValue) { _, _ in hasEdited = true }
            // Without this VoiceOver reads a bare number with no idea which
            // column it came from.
            .accessibilityLabel(placeholder == "kg" ? "Weight in kilograms" : "Repetitions")
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
