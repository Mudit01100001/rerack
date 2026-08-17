import WidgetKit
import SwiftUI
import ActivityKit
import UIKit

@main
struct RerackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        WorkoutSelectorWidget()
        TrainingStatsWidget()
    }
}

/// PRD §8 / docs/M6-live-activity-design.md. One layout family: the next
/// thing you will do, the exact numbers a tick will write, and a tick —
/// plus a countdown and Skip while resting. Nothing else ever appears.
///
/// This file renders pre-composed strings only (M6 §8): no SwiftData, no
/// GhostSetResolver, no formatting decisions. If wording looks wrong, fix
/// the composer in `LiveActivityController`, not here.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                // Translucent black rather than the flat near-opaque grey
                // this used to be. The grey read as a slab dropped on the
                // wallpaper; black at 55% keeps the same contrast for white
                // text — the payload still passes at a glance in bad gym
                // light — while letting the Lock Screen show through, which
                // is what every system-supplied Live Activity does.
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // M6 §4.2 region mapping.
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.compactToken)
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let restEndsAt = context.state.restEndsAt {
                        Text(timerInterval: Date()...max(restEndsAt, Date()), countsDown: true)
                            .font(.caption.monospacedDigit())
                            .frame(maxWidth: 50)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exerciseName ?? context.state.positionLabel)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PayloadRow(context: context, showsAdjust: false)
                }
            } compactLeading: {
                Text(context.state.compactToken)
                    .font(.caption2.bold())
                    .foregroundStyle(.tint)
            } compactTrailing: {
                // M6 §4.3: while resting, the countdown; while logging, the
                // payload. Mutually exclusive, typographically distinct, and
                // the slot's job is stable — "the number that matters now."
                if let restEndsAt = context.state.restEndsAt {
                    Text(timerInterval: Date()...max(restEndsAt, Date()), countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 40)
                } else {
                    Text(compactPayload(context.state.payload, unit: context.state.unit))
                        .font(.caption2.monospacedDigit())
                }
            } minimal: {
                // M6 §4.4: minimal exists because another app's activity is
                // more important right now; it should not compete.
                if let restEndsAt = context.state.restEndsAt {
                    Text(timerInterval: Date()...max(restEndsAt, Date()), countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(.tint)
                }
            }
            .widgetURL(WorkoutDeepLink.active)
        }
    }

    /// `12×6`, ≤6 glyphs or weight alone; `—` when unknown (M6 §4.3).
    private func compactPayload(_ payload: WorkoutActivityAttributes.ContentState.Payload, unit: UnitPreference) -> String {
        switch payload {
        case .known(let weightKg, let reps):
            let weight = Weight.format(kg: weightKg, in: unit)
            let composed = "\(weight)×\(reps)"
            return composed.count > 6 ? weight : composed
        case .repsOnly(let reps):
            return "×\(reps)"
        case .unknown:
            return "—"
        }
    }
}

// MARK: - Lock Screen (M6 §4.1 — the primary surface)

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.workoutTitle.uppercased())
                    .font(.caption2)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 64, alignment: .trailing)
            }

            HStack(spacing: 10) {
                ExerciseThumbnail(assetName: context.state.exerciseImageName)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let supersetLabel = context.state.supersetLabel {
                            Text(supersetLabel)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                        Text(context.state.exerciseName ?? context.state.positionLabel)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    // Item 5: while resting, the exercise name next to the
                    // thumbnail is enough. Repeating "Next: Set 2 of 3 ·
                    // 20 kg × 5" under it tripled the reading load on the
                    // one surface that has to be understood at a glance,
                    // and the same numbers reappear in the payload row the
                    // moment rest ends.
                    if context.state.exerciseName != nil, context.state.restEndsAt == nil {
                        Text(context.state.positionLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let restEndsAt = context.state.restEndsAt {
                RestControls(
                    workoutID: context.attributes.workoutID,
                    startedAt: context.state.restStartedAt ?? Date(),
                    endsAt: restEndsAt
                )
            } else {
                PayloadRow(context: context, showsAdjust: true)
            }

            if let thenLine = context.state.thenLine, context.state.restEndsAt == nil {
                Text(thenLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

}

/// Round exercise thumbnail. Renders a dumbbell glyph until real artwork is
/// dropped in — `exerciseImageName` is already carried end-to-end, so adding
/// images later means adding files to the asset catalogue and nothing else.
private struct ExerciseThumbnail: View {
    let assetName: String?

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let assetName, UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 40, height: 40)
    }
}

/// The resting control set: an on-device progress bar plus −15s / countdown /
/// +15s / Skip. `ProgressView(timerInterval:)` animates without any update
/// push (M6 §P3/§P5), so the bar costs nothing to keep live.
private struct RestControls: View {
    let workoutID: UUID
    let startedAt: Date
    let endsAt: Date

    var body: some View {
        VStack(spacing: 8) {
            // Item 5: this is a *timer*, so the bar drains. It used to fill
            // left-to-right, which is stopwatch behaviour and read as "time
            // accumulating" when the thing being shown is time remaining —
            // a full bar meant rest was over, the opposite of the intuition.
            ProgressView(timerInterval: startedAt...max(endsAt, startedAt.addingTimeInterval(1)), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Color.accentColor)

            HStack(spacing: 8) {
                Button(intent: AdjustRestIntent(workoutID: workoutID, deltaSeconds: -15)) {
                    Text("−15s")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(minWidth: 54, minHeight: 40)
                        .background(SecondaryActionBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reduce rest by 15 seconds")

                Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
                    .font(.title3.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button(intent: AdjustRestIntent(workoutID: workoutID, deltaSeconds: 15)) {
                    Text("+15s")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(minWidth: 54, minHeight: 40)
                        .background(SecondaryActionBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add 15 seconds to rest")

                Button(intent: SkipRestIntent(workoutID: workoutID)) {
                    Text("Skip")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 62, minHeight: 40)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
            }
        }
    }
}

// MARK: - Payload + buttons (shared by Lock Screen and expanded island)

/// Exactly one highlighted control per state. The filled accent capsule is
/// reserved for the action you actually came here to take — ✓ while logging,
/// `Finish` when nothing's left, `Open` when the payload can't be trusted.
/// Skip is real but secondary, so it reads as an outline on the card's own
/// background rather than competing with a second filled pill.
private struct SecondaryActionBackground: View {
    var body: some View {
        Capsule()
            .fill(.clear)
            .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
}

/// Rank 1 above rank 2 (M6 §2): if the numbers can't be shown, the button
/// must not be shown either. A button whose payload is invisible is a button
/// that writes something you didn't agree to.
private struct PayloadRow: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    let showsAdjust: Bool

    private var isFinishState: Bool { context.state.workoutExerciseID == nil }

    var body: some View {
        HStack(spacing: 10) {
            payloadText
            Spacer(minLength: 4)

            if showsAdjust, let focusURL = focusURL {
                Link(destination: focusURL) {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Adjust this set")
            }

            if context.state.restEndsAt != nil {
                Button(intent: SkipRestIntent(workoutID: context.attributes.workoutID)) {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 60, minHeight: 44)
                        .background(SecondaryActionBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
            }

            trailingAction
        }
    }

    @ViewBuilder
    private var payloadText: some View {
        switch context.state.payload {
        case .known(let weightKg, let reps):
            Text("\(Weight.format(kg: weightKg, in: context.state.unit, includeUnit: true)) × \(reps)")
                .font(.title3.monospacedDigit())
        case .repsOnly(let reps):
            Text("\(reps) reps")
                .font(.title3.monospacedDigit())
        case .unknown:
            // In the finish state the headline row already says "All planned
            // sets logged" — repeating it here would double the line (§4.1's
            // sketch leaves this slot empty).
            if !isFinishState {
                Text("No target yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The tick — or its honest replacements. Stale (§7 row 32) and unknown
    /// payload (§5.3) both get `Open`; all-planned-logged gets `Finish`
    /// (a deep link, never an intent — §6.3).
    @ViewBuilder
    private var trailingAction: some View {
        if isFinishState {
            Link(destination: WorkoutDeepLink.finish) {
                Text("Finish")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 72, minHeight: 44)
                    .background(Color.accentColor, in: Capsule())
            }
            .accessibilityLabel("Finish workout")
        } else if context.isStale || !isPayloadKnown {
            Link(destination: focusURL ?? WorkoutDeepLink.active) {
                Text("Open")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 72, minHeight: 44)
                    .background(Color.accentColor, in: Capsule())
            }
            .accessibilityLabel("Open in \(context.attributes.workoutTitle) to enter values")
        } else {
            Button(intent: logIntent) {
                Image(systemName: "checkmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 72, minHeight: 44)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log this set")
        }
    }

    private var isPayloadKnown: Bool {
        if case .unknown = context.state.payload { return false }
        return true
    }

    private var focusURL: URL? {
        context.state.workoutExerciseID.map {
            WorkoutDeepLink.focus(workoutExerciseID: $0, setIndex: context.state.setIndex)
        }
    }

    /// M6 §6.1: the intent carries the displayed values, byte for byte.
    private var logIntent: LogSetIntent {
        let (weight, reps): (Double, Int) = {
            switch context.state.payload {
            case .known(let weightKg, let reps): return (weightKg, reps)
            case .repsOnly(let reps): return (0, reps)
            case .unknown: return (0, 0) // unreachable — no tick is rendered
            }
        }()
        return LogSetIntent(
            workoutID: context.attributes.workoutID,
            workoutExerciseID: context.state.workoutExerciseID ?? UUID(),
            setIndex: context.state.setIndex,
            weightKg: weight,
            reps: reps
        )
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
