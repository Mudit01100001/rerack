import SwiftUI

/// PRD §7.5: wall-clock based — driven by an absolute end instant, not a
/// running counter, so backgrounding can't cause drift. Uses
/// `Text(timerInterval:)` / `ProgressView(timerInterval:)`, which redraw
/// natively with zero app-driven updates — the same mechanism the Live
/// Activity countdown uses (§8.7), just in an ordinary view here.
///
/// Since M6 §9.2 both the start and end instants come from `Workout`, so this
/// bar, the local notification, and the island all count down to the same
/// moment rather than each deriving one from a duration of their own.
struct RestTimerBar: View {
    let restStartedAt: Date
    let restEndsAt: Date
    let onSkip: () -> Void
    /// Absolute, not a delta. The in-app control is now a slider, so it
    /// answers "how long left" rather than "add fifteen seconds" — the Live
    /// Activity keeps ±15s buttons, where a slider has no room and a
    /// thumb-sized target on the Lock Screen is worth more than precision.
    let onSetRemaining: (Int) -> Void

    /// Live value while the thumb is down. The bar's own source of truth is
    /// `restEndsAt`, which is moving every second — binding a slider straight
    /// to it makes the thumb fight the countdown under your finger.
    @State private var scrubbedRemaining: Double?

    /// Ceiling for the slider. Anchored to the rest that was actually
    /// configured so the thumb starts mid-track rather than pinned right, and
    /// floored at three minutes so a short rest still has room to grow.
    private var maximumSeconds: Double {
        max(restEndsAt.timeIntervalSince(restStartedAt), 180).rounded()
    }

    private var remainingNow: Double {
        max(restEndsAt.timeIntervalSinceNow, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            header

            // Drains rather than fills. This read `countsDown: false`, so a
            // *full* bar meant rest was over — the exact opposite of what a
            // countdown implies, and the same inversion the Lock Screen had.
            ProgressView(timerInterval: restStartedAt...restEndsAt, countsDown: true)
                .tint(.accentColor)
                .labelsHidden()

            slider
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

    private var slider: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "minus")
                .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                .foregroundStyle(.tertiary)

            Slider(
                value: Binding(
                    get: { scrubbedRemaining ?? min(remainingNow, maximumSeconds) },
                    set: { scrubbedRemaining = $0 }
                ),
                in: 0...maximumSeconds,
                step: 5,
                onEditingChanged: { editing in
                    if editing {
                        Haptics.play(.selection)
                    } else if let value = scrubbedRemaining {
                        onSetRemaining(Int(value))
                        scrubbedRemaining = nil
                    }
                }
            )
            .tint(.accentColor)
            .onChange(of: scrubbedRemaining.map { Int($0 / 5) }) { old, new in
                guard old != nil, new != nil, old != new else { return }
                Haptics.play(.scrubTick)
            }

            Image(systemName: "plus")
                .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                .foregroundStyle(.tertiary)

            Button(action: onSkip) {
                Text("Skip")
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.leading, DS.Space.xxs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest remaining")
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
