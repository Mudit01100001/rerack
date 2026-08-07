import SwiftUI

/// PRD §7.5: wall-clock based — computed from `restStartedAt` + a duration,
/// not a running counter, so backgrounding can't cause drift. Uses
/// `Text(timerInterval:)` / `ProgressView(timerInterval:)`, which redraw
/// natively with zero app-driven updates — the same mechanism the future
/// Live Activity countdown will use (§8.7), just in an ordinary view here.
struct RestTimerBar: View {
    let restStartedAt: Date
    let durationSeconds: Int
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    private var endDate: Date {
        restStartedAt.addingTimeInterval(TimeInterval(max(durationSeconds, 1)))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Resting")
                    .font(.caption.bold())
                Spacer()
                Text(timerInterval: restStartedAt...endDate, countsDown: true)
                    .font(.caption.monospacedDigit())
            }
            ProgressView(timerInterval: restStartedAt...endDate, countsDown: false)
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
