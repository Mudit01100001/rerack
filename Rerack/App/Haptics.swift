import UIKit
import CoreHaptics

/// One vocabulary for how the app feels, because before this the entire
/// codebase contained a single `UINotificationFeedbackGenerator` call and a
/// full workout could be logged without one felt response.
///
/// Two engines sit behind this. Simple taps go through `UIFeedbackGenerator`,
/// which is cheap and always available. The three moments that carry emotional
/// weight — a rest timer ending, a PR, the confetti — go through Core Haptics
/// so they can be *patterns* rather than a single thud: a chime you feel.
///
/// Every call is safe to make from anywhere. If the device has no haptic
/// engine (iPad, Simulator) or the user has switched system haptics off, the
/// calls are inert rather than a crash or a stutter.
@MainActor
enum Haptics {

    // MARK: - Vocabulary

    enum Event {
        /// A set is ticked. The most-repeated haptic in the app, so it is
        /// deliberately the lightest thing that still registers — anything
        /// heavier becomes fatiguing over 30 sets.
        case setCompleted
        /// A set is un-ticked. Softer and duller than completing, so the two
        /// are distinguishable without looking.
        case setUncompleted
        /// A set row was added, by button or by swipe.
        case setAdded
        /// A row was deleted. Deliberately firmer — destructive actions
        /// should feel like they happened.
        case setDeleted
        /// A drop set was chained onto a parent.
        case dropAdded
        /// A swipe has travelled far enough that releasing will fire. Fires
        /// once per crossing, which is what makes a swipe feel detented
        /// rather than mushy.
        case swipeThreshold
        /// The number scrubber passed a whole unit while dragging.
        case scrubTick
        /// Rest timer adjusted (slider, ±15s).
        case timerAdjusted
        /// Rest skipped by hand.
        case timerSkipped
        /// Rest hit zero on its own. A rising two-tap chime — the one moment
        /// in a workout the app is telling *you* something rather than
        /// acknowledging you, so it is the only ascending pattern.
        case restComplete
        /// A personal record was detected.
        case personalRecord
        /// The finish-screen confetti. A soft burst that decays, timed to
        /// the fall rather than fired once at the top.
        case celebration
        /// A destructive or invalid action was refused.
        case failure
        /// Generic selection change — pickers, segment changes, menu items.
        case selection
    }

    // MARK: - Entry point

    static func play(_ event: Event) {
        guard enabled else { return }
        switch event {
        case .setCompleted:   impact(.light, intensity: 0.7)
        case .setUncompleted: impact(.soft, intensity: 0.5)
        case .setAdded:       impact(.light, intensity: 0.6)
        case .setDeleted:     impact(.rigid, intensity: 0.9)
        case .dropAdded:      impact(.medium, intensity: 0.7)
        case .swipeThreshold: impact(.rigid, intensity: 0.6)
        case .scrubTick:      selectionChanged()
        case .timerAdjusted:  selectionChanged()
        case .timerSkipped:   impact(.soft, intensity: 0.6)
        case .selection:      selectionChanged()
        case .failure:        notification(.error)
        case .restComplete:
            if !playPattern(.restChime) { notification(.success) }
        case .personalRecord:
            if !playPattern(.personalRecord) { notification(.success) }
        case .celebration:
            if !playPattern(.celebration) { notification(.success) }
        }
    }

    /// Haptics respect the same accessibility switch as the rest of the
    /// system. `UIDevice` exposes no "haptics on" flag, so this tracks the
    /// one condition we can read — a device without the Taptic Engine — and
    /// otherwise lets the system swallow the request, which it does silently
    /// when the user has turned haptics off in Settings.
    private static var enabled: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - Simple generators

    /// Generators are cached and pre-warmed. A freshly-allocated generator
    /// has to spin the Taptic Engine up, which lands the first tap of a
    /// session tens of milliseconds late — enough that the very first set of
    /// a workout felt unresponsive while every later one felt fine.
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let generator = impactGenerators[style] ?? {
            let new = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = new
            return new
        }()
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    private static func selectionChanged() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    private static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// Call once on app launch and whenever a workout starts. Without this
    /// the engine idles down between exercises and the first tick after a
    /// long rest arrives late.
    static func warmUp() {
        guard enabled else { return }
        selectionGenerator.prepare()
        notificationGenerator.prepare()
        _ = engine
    }

    // MARK: - Core Haptics patterns

    private static var engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try? CHHapticEngine()
        // The engine is stopped by the system on interruption (a call, going
        // to background) and does *not* restart itself. Without these two
        // handlers the first interruption would silently kill every rich
        // haptic for the rest of the process's life.
        engine?.stoppedHandler = { _ in try? engine?.start() }
        engine?.resetHandler = { try? engine?.start() }
        try? engine?.start()
        return engine
    }()

    @discardableResult
    private static func playPattern(_ pattern: HapticPattern) -> Bool {
        guard let engine, let events = try? pattern.events() else { return false }
        do {
            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }
}

/// The three moments that get a genuine Core Haptics *pattern* rather than a
/// single tap. Kept at file scope so the pattern bodies can live in their own
/// extension without tripping over nested-type access control.
enum HapticPattern {
    case restChime
    case personalRecord
    case celebration
}

extension HapticPattern {

    fileprivate func events() throws -> [CHHapticEvent] {
        switch self {
        case .restChime:
            // Two taps, the second sharper and slightly stronger. Rising
            // brightness is what makes it read as "go" rather than "stop" —
            // the same trick a doorbell uses.
            return [
                event(intensity: 0.6, sharpness: 0.3, at: 0),
                event(intensity: 1.0, sharpness: 0.8, at: 0.12)
            ]

        case .personalRecord:
            // Three ascending taps then a short swell. Longer than anything
            // else in the app on purpose: a PR should feel like an event,
            // and it can afford the time because it interrupts nothing.
            return [
                event(intensity: 0.5, sharpness: 0.4, at: 0),
                event(intensity: 0.7, sharpness: 0.6, at: 0.09),
                event(intensity: 1.0, sharpness: 0.9, at: 0.18),
                continuous(intensity: 0.55, sharpness: 0.5, at: 0.26, duration: 0.28)
            ]

        case .celebration:
            // Scattered taps decaying over ~0.9s, matched to the confetti's
            // fall rather than fired as one burst at the top. The offsets are
            // irregular on purpose — evenly spaced taps read as a machine.
            let offsets: [(TimeInterval, Float)] = [
                (0.00, 1.00), (0.07, 0.72), (0.13, 0.88), (0.22, 0.55),
                (0.31, 0.70), (0.42, 0.45), (0.55, 0.55), (0.71, 0.32),
                (0.90, 0.24)
            ]
            return offsets.map { offset, intensity in
                event(intensity: intensity, sharpness: 0.35 + intensity * 0.4, at: offset)
            }
        }
    }

    fileprivate func event(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    fileprivate func continuous(intensity: Float, sharpness: Float, at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }
}
