import SwiftUI

/// Press-and-hold a weight or reps field, then drag up or down to change it
/// without the keyboard (PRD §7.2, added after a full-workout test found that
/// nudging a number from 20 to 22.5 cost a keyboard summon, a select-all and
/// four taps).
///
/// The gesture is deliberately gated behind a hold. A bare vertical drag on
/// these fields would fight the scroll view, and a bare tap must keep opening
/// the keyboard — typing stays the fast path for a value that changes a lot,
/// scrubbing is for a nudge.
struct NumberScrubModifier: ViewModifier {
    @Binding var text: String
    /// One detent. 2.5 for kilos matches the smallest plate pair most gyms
    /// have; 1 for reps.
    let step: Double
    let range: ClosedRange<Double>
    /// Reps render as integers, weight keeps a decimal only when it needs one.
    let formatsAsInteger: Bool
    var onCommit: () -> Void = {}

    @State private var isScrubbing = false
    @State private var startValue: Double = 0
    @State private var lastSteppedValue: Double = 0

    /// Vertical travel per detent. Tuned by hand: 7pt was twitchy enough to
    /// overshoot on a moving bus, 16pt made a 20 kg change a two-swipe job.
    private let pointsPerStep: CGFloat = 11

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isScrubbing { scrubBadge }
            }
            .scaleEffect(isScrubbing ? 1.08 : 1)
            .animation(.snappy(duration: 0.18), value: isScrubbing)
            .gesture(scrubGesture)
    }

    /// The value floats above the field while scrubbing. The field itself is
    /// small and under the thumb mid-drag, so without this the number being
    /// changed is the one thing on screen you cannot see.
    private var scrubBadge: some View {
        Text(format(current))
            .dsFont(DS.TypeScale.heading, relativeTo: .title3, weight: .semibold, design: .rounded)
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(Color.accentColor)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            )
            .offset(y: -44)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .allowsHitTesting(false)
    }

    private var current: Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .onEnded { _ in
                startValue = current
                lastSteppedValue = current
                isScrubbing = true
                Haptics.play(.selection)
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                guard isScrubbing else { return }
                // Up is more, which matches every stepper and slider in iOS —
                // and screen coordinates run the other way, hence the negation.
                let steps = (-drag.translation.height / pointsPerStep).rounded()
                let proposed = (startValue + steps * step)
                    .clamped(to: range)
                let snapped = (proposed / step).rounded() * step
                guard snapped != lastSteppedValue else { return }
                lastSteppedValue = snapped
                text = format(snapped)
                Haptics.play(.scrubTick)
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                isScrubbing = false
                onCommit()
            }
    }

    private func format(_ value: Double) -> String {
        if formatsAsInteger || value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

extension View {
    /// `step` is the detent size, `range` clamps it, `formatsAsInteger` drops
    /// the decimal for reps.
    func numberScrub(
        text: Binding<String>,
        step: Double,
        range: ClosedRange<Double>,
        formatsAsInteger: Bool,
        onCommit: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            NumberScrubModifier(
                text: text,
                step: step,
                range: range,
                formatsAsInteger: formatsAsInteger,
                onCommit: onCommit
            )
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
