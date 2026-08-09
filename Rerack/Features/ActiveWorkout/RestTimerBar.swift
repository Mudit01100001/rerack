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
    let onAdjust: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Resting")
                    .font(.caption.bold())
                Spacer()
                Text(timerInterval: restStartedAt...restEndsAt, countsDown: true)
                    .font(.caption.monospacedDigit())
            }
            ProgressView(timerInterval: restStartedAt...restEndsAt, countsDown: false)
                .tint(.accentColor)
            HStack {
                Button("−15s") { onAdjust(-15) }
                    .font(.caption)
                Button("+15s") { onAdjust(15) }
                    .font(.caption)
                Spacer()
                Button("Skip", action: onSkip)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
