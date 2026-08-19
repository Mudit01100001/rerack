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
    /// Build 5 item C: renamed from `onDeleteExisting` now that Delete is
    /// offered on every top-level row, not just a completed one — the old
    /// name implied a row had to already exist as a logged `SetLog` to be
    /// deletable, which is exactly the gate that made an un-ticked row
    /// un-swipeable in the first place. The closure itself is unconditional
    /// here; whether deleting is *possible* is the caller's call (for a
    /// drop row it always is — see `dropChainRows` in `ExerciseCardView`).
    let onDeleteRow: () -> Void
    /// nil hides the "+ Drop" swipe action — callers only pass a closure for
    /// a completed row (PRD §15: blocked on an incomplete parent).
    var onAddDrop: (() -> Void)? = nil
    /// Leading swipe: append another set carrying this row's values. nil on
    /// drop rows, where "one more like that" has no meaning — a chain is
    /// extended with `+ Drop`, not duplicated.
    var onDuplicate: ((_ weightKg: Double, _ reps: Int) -> Void)? = nil

    @Environment(\.dominantHand) private var dominantHand
    @Environment(\.unitPreference) private var unit

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var hasEdited = false
    /// PRD §7.3: "Ghost becomes editable, pre-selected so typing replaces it."
    /// It didn't — tapping a ghost of `0` and typing `60` produced `600`, and
    /// the set logged at 600 kg with a straight face. SwiftUI has no
    /// select-all for `TextField`, so the field clears on focus instead and
    /// restores the ghost if you leave without typing. The value is never
    /// lost: the PREVIOUS column still shows it either way.
    @FocusState private var focusedField: Field?
    /// Which fields the user has actually typed into. Tracked per field
    /// because clearing is per field: editing the weight must not stop the
    /// reps ghost from clearing when you move to it.
    @State private var editedFields: Set<Field> = []

    private enum Field: Hashable { case weight, reps }

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
        SwipeActionRow(leading: leadingActions, trailing: trailingActions) {
            HStack(spacing: DS.Space.xs) {
                if dominantHand == .left {
                    tickButton
                }
                rowContent
                if dominantHand == .right {
                    tickButton
                }
            }
        }
        .onAppear(perform: populate)
        .onChange(of: existingSet?.id) { _, _ in populate() }
        .onChange(of: existingSet?.isCompleted) { _, _ in populate() }
        .onChange(of: unit) { _, _ in populate() }
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
        let weight = weightText.isEmpty ? "no weight" : "\(weightText) \(unit == .kg ? "kilograms" : "pounds")"
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
                    Text("\(Weight.format(kg: ghost.weightKg, in: unit))×\(ghost.reps)")
                } else {
                    Text("-")
                }
            }
            .dsFont(DS.TypeScale.caption, relativeTo: .caption, design: .rounded)
            .foregroundStyle(.tertiary)
            .frame(width: 66, alignment: .leading)

            entryField(
                text: $weightText,
                placeholder: unit.abbreviation,
                width: 58,
                keyboard: .decimalPad,
                field: .weight,
                // One plate pair, expressed in whatever unit is on screen —
                // scrubbing in 2.5 lb steps would be uselessly fine.
                scrubStep: unit == .kg ? 2.5 : 5,
                scrubRange: 0...1000,
                scrubsAsInteger: false
            )
            entryField(
                text: $repsText,
                placeholder: "reps",
                width: 48,
                keyboard: .numberPad,
                field: .reps,
                scrubStep: 1,
                scrubRange: 0...100,
                scrubsAsInteger: true
            )

            Spacer(minLength: 0)
        }
    }

    /// PRD §7.3/§7.9. These used to be declared with `.swipeActions`, which
    /// `List` alone honours — inside this card's `VStack` the modifier was
    /// inert, so Delete and `+ Drop` were unreachable for the whole of V1.
    /// `SwipeActionRow` reimplements the interaction for a non-`List` row.
    private var trailingActions: [SwipeAction] {
        var actions: [SwipeAction] = []
        // PRD §7.9/§7.4: offered only on a completed row — the caller
        // withholds `onAddDrop` entirely for anything not yet ticked
        // (§15 "drop set added to an incomplete parent" is blocked).
        if let onAddDrop {
            actions.append(
                SwipeAction(label: "Drop", systemImage: "arrow.turn.down.right", tint: .orange) {
                    Haptics.play(.dropAdded)
                    onAddDrop()
                }
            )
        }
        // Build 5 item C: Delete is unconditional now, not gated on
        // `existingSet != nil`. A row that never became a `SetLog` — an
        // un-ticked ghost, or an existing-but-un-ticked row the caller
        // withholds `existingSet` for (see `ExerciseCardView.setList`) — is
        // still a slot on screen the user planned and wants gone; the old
        // gate is exactly why those rows had no swipe action at all.
        actions.append(
            SwipeAction(label: "Delete", systemImage: "trash", tint: .red, isDestructive: true) {
                onDeleteRow()
            }
        )
        return actions
    }

    private var leadingActions: [SwipeAction] {
        guard let onDuplicate else { return [] }
        return [
            SwipeAction(label: "Add Set", systemImage: "plus", tint: .accentColor) {
                let weightKg = Weight.parseToKilograms(weightText, in: unit) ?? 0
                onDuplicate(weightKg, Int(repsText) ?? 0)
            }
        ]
    }

    /// Editable fields carry a filled background and a border; static text
    /// doesn't. That's the app-wide rule now — if you can change it, it looks
    /// like a control.
    private func entryField(
        text: Binding<String>,
        placeholder: String,
        width: CGFloat,
        keyboard: UIKeyboardType,
        field: Field,
        scrubStep: Double,
        scrubRange: ClosedRange<Double>,
        scrubsAsInteger: Bool
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
            .focused($focusedField, equals: field)
            .onChange(of: focusedField) { previous, current in
                if current == field, !isCompleted, !editedFields.contains(field) {
                    text.wrappedValue = ""
                } else if previous == field, text.wrappedValue.isEmpty, !editedFields.contains(field) {
                    // Focused, typed nothing, left — put the suggestion back.
                    populate()
                }
            }
            // "Edited" is decided by *focus*, not by the text changing.
            // `populate()` writes into these bindings on appear, on unit
            // change and on every row identity change, and each of those
            // fired the old unconditional handler — so `hasEdited` was
            // already true before the field was ever touched, which is why
            // the clear-on-focus above never ran and typing 60 over a ghost
            // 0 logged 600.
            .onChange(of: text.wrappedValue) { _, newValue in
                guard focusedField == field, !newValue.isEmpty else { return }
                editedFields.insert(field)
                hasEdited = true
            }
            // §7.2: press-and-hold, then drag up or down to nudge the value
            // without summoning the keyboard.
            .numberScrub(
                text: text,
                step: scrubStep,
                range: scrubRange,
                formatsAsInteger: scrubsAsInteger,
                onCommit: {
                    // Scrubbing never focuses the field, so it has to declare
                    // the edit itself.
                    editedFields.insert(field)
                    hasEdited = true
                }
            )
            // Without this VoiceOver reads a bare number with no idea which
            // column it came from.
            .accessibilityLabel(placeholder == "reps" ? "Repetitions" : "Weight in \(unit == .kg ? "kilograms" : "pounds")")
            .accessibilityHint("Press and hold, then drag up or down to change")
    }

    private func populate() {
        if focusedField == nil { editedFields.removeAll() }
        if let existingSet {
            weightText = Weight.format(kg: existingSet.addedWeightKg, in: unit)
            // §7.9: reps genuinely vary set-to-set on a drop, so an un-ticked
            // drop added by hand carries `reps == 0` as "not guessed yet"
            // rather than a fact-shaped lie (Principle 5). A reproduced chain
            // does carry last session's reps, and shows them.
            repsText = (!existingSet.isCompleted && existingSet.reps == 0) ? "" : String(existingSet.reps)
            hasEdited = existingSet.isCompleted
        } else if let ghost {
            weightText = Weight.format(kg: ghost.weightKg, in: unit)
            repsText = String(ghost.reps)
            hasEdited = false
        } else if let dropPrefillWeightKg {
            // §7.9: only the weight is pre-filled — reps genuinely vary
            // set-to-set on a drop, so guessing one would be a fact-shaped
            // lie (PRD §4 Principle 5).
            weightText = Weight.format(kg: dropPrefillWeightKg, in: unit)
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
            Haptics.play(.setUncompleted)
            onUncomplete()
        } else {
            // PRD §7.2: empty reps blocks completion; 0 kg is allowed
            // (bodyweight exercises, §13.1).
            guard let reps = Int(repsText), reps > 0 else {
                // Silently doing nothing on a tap reads as a broken button.
                Haptics.play(.failure)
                return
            }
            let weightKg = Weight.parseToKilograms(weightText, in: unit) ?? 0
            Haptics.play(.setCompleted)
            onComplete(weightKg, reps)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
