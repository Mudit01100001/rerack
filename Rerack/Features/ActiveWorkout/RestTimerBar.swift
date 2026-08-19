import SwiftUI

/// PRD §7.5: wall-clock based — driven by an absolute end instant, not a
/// running counter, so backgrounding can't cause drift. The header uses
/// `Text(timerInterval:)`, which redraws natively with zero app-driven
/// updates — the same mechanism the Live Activity countdown uses (§8.7),
/// just in an ordinary view here. The track below it ticks off a
/// `TimelineView` for the same reason: no `Timer` for this view to own,
/// invalidate, or leak.
///
/// Since M6 §9.2 both the start and end instants come from `Workout`, so this
/// bar, the local notification, and the island all count down to the same
/// moment rather than each deriving one from a duration of their own.
struct RestTimerBar: View {
    let restStartedAt: Date
    let restEndsAt: Date
    let onSkip: () -> Void
    /// Absolute, not a delta. The in-app control answers "how long left" by
    /// dragging a position, not "add fifteen seconds" — the Live Activity
    /// keeps ±15s buttons, where the track has no room and a thumb-sized
    /// target on the Lock Screen is worth more than precision.
    let onSetRemaining: (Int) -> Void

    /// Live value while a finger is down on the track. The bar's own source
    /// of truth is `restEndsAt`, which is moving every second — driving the
    /// fill straight from it while dragging would make the thumb fight the
    /// countdown under your finger.
    @State private var scrubbedRemaining: Double?

    /// Ceiling for the track. Anchored to the rest that was actually
    /// configured so the thumb starts mid-track rather than pinned right, and
    /// floored at three minutes so a short rest still has room to grow.
    private var maximumSeconds: Double {
        max(restEndsAt.timeIntervalSince(restStartedAt), 180).rounded()
    }

    private var remainingNow: Double {
        max(restEndsAt.timeIntervalSinceNow, 0)
    }

    /// 22pt matches the touch target Apple's own sliders use; the track
    /// itself stays a slim 14pt so the thumb visibly overhangs it top and
    /// bottom, the same way a system slider's knob overhangs its groove.
    private let thumbDiameter: CGFloat = 22
    private let trackHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            header
            track
            footer
        }
        .padding(DS.Space.sm)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Resting", systemImage: "hourglass")
                .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .bold)
                .foregroundStyle(.secondary)
            Spacer()
            // §10: the rest countdown is the biggest number on screen while
            // resting, so there is never a question about which clock is
            // which. The session total sits in the header above, in a pill,
            // deliberately quieter.
            Group {
                if let scrubbedRemaining {
                    Text(clock(Int(scrubbedRemaining)))
                } else {
                    Text(timerInterval: restStartedAt...restEndsAt, countsDown: true)
                }
            }
            .dsFont(DS.TypeScale.heading, relativeTo: .title2, weight: .semibold, design: .rounded)
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }

    /// The track *is* the control now: one capsule that shows the remaining
    /// fraction and can be dragged to change it, replacing the progress bar
    /// and slider that used to sit stacked as two widgets answering the same
    /// question — "how much rest is left" was drawn twice, and only one of
    /// the two drawings was draggable.
    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            TimelineView(.periodic(from: restStartedAt, by: 1)) { context in
                // While a drag is live, `scrubbedRemaining` wins over the
                // clock so the fill tracks the finger instead of snapping
                // back mid-gesture; once the finger lifts this falls back to
                // reading straight off `restEndsAt`, same as the header.
                let filledFraction = scrubbedRemaining.map { fraction(of: $0) }
                    ?? fraction(of: max(restEndsAt.timeIntervalSince(context.date), 0))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: width * filledFraction, height: trackHeight)
                    thumb
                        .offset(x: width * filledFraction - thumbDiameter / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: thumbDiameter)
        .accessibilityElement()
        .accessibilityLabel("Rest remaining")
        .accessibilityValue(clock(Int(scrubbedRemaining ?? remainingNow)))
        // VoiceOver users get the same ±15s the Live Activity's buttons give
        // — a swipe-up/down gesture instead of a drag they can't perform
        // precisely without sighted feedback.
        .accessibilityAdjustableAction { direction in
            let current = scrubbedRemaining ?? remainingNow
            let step: Double = direction == .increment ? 15 : -15
            onSetRemaining(Int((current + step).clamped(to: 0...maximumSeconds)))
        }
    }

    /// White so it reads against the fill and the empty track alike, with a
    /// `.regularMaterial` centre inset from that white so the same frosted
    /// surface as the bar's own container shows through the handle rather
    /// than a second, unrelated material.
    private var thumb: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().fill(.regularMaterial).padding(3))
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
    }

    /// A single row under the track — no ± glyphs, no second control. `Skip`
    /// stays a plain text button so it doesn't visually compete with the
    /// track, which is the thing actually worth touching.
    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onSkip) {
                Text("Skip")
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    /// `minimumDistance: 0` so a tap sets the value immediately — the whole
    /// track is the hit target, not just the thumb, the same way tapping
    /// anywhere on a system slider's groove jumps the knob there.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                let fraction = (value.location.x / width).clamped(to: 0...1)
                let seconds = (fraction * maximumSeconds).rounded()
                let previousStep = scrubbedRemaining.map { Int($0 / 5) }
                if previousStep == nil {
                    Haptics.play(.selection)
                } else if previousStep != Int(seconds / 5) {
                    Haptics.play(.scrubTick)
                }
                scrubbedRemaining = seconds
            }
            .onEnded { value in
                guard width > 0 else { return }
                let fraction = (value.location.x / width).clamped(to: 0...1)
                // Dragging all the way to the left is a legitimate "end rest
                // now", not a minimum to clamp away from, so 0 is allowed
                // through untouched.
                onSetRemaining(Int((fraction * maximumSeconds).rounded()))
                scrubbedRemaining = nil
            }
    }

    /// Remaining seconds, expressed as a fraction of `maximumSeconds` for
    /// the track's width. Shared by the live (clock-driven) and scrubbed
    /// (finger-driven) paths so both draw the fill identically.
    private func fraction(of remainingSeconds: Double) -> Double {
        (remainingSeconds / maximumSeconds).clamped(to: 0...1)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
