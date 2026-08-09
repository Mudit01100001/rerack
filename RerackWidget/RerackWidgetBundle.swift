import WidgetKit
import SwiftUI
import ActivityKit

@main
struct RerackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
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
                // Opaque, not translucent: a see-through card puts the
                // wallpaper behind the payload, and the payload is the one
                // thing that has to stay readable at a glance in bad gym
                // light. Near-black matches the app icon's ground.
                .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.08))
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
                    Text(compactPayload(context.state.payload))
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
    private func compactPayload(_ payload: WorkoutActivityAttributes.ContentState.Payload) -> String {
        switch payload {
        case .known(let weightKg, let reps):
            let weight = weightKg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weightKg)) : String(weightKg)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(context.attributes.workoutTitle.uppercased())
                    .font(.caption2)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                if let restEndsAt = context.state.restEndsAt {
                    Text(timerInterval: Date()...max(restEndsAt, Date()), countsDown: true)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 56, alignment: .trailing)
                }
            }

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
                Spacer()
                if context.state.exerciseName != nil {
                    Text(context.state.positionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PayloadRow(context: context, showsAdjust: true)

            if let thenLine = context.state.thenLine {
                Text(thenLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
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
            Text("\(formattedWeight(weightKg)) kg × \(reps)")
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
