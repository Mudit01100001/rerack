import UIKit
import CoreHaptics

/// One vocabulary for how the app feels, because before this the entire
/// codebase contained a single `UINotificationFeedbackGenerator` call and a
/// full workout could be logged without one felt response.
///
/// Two engines sit behind this. Simple taps go through `UIFeedbackGenerator`
/// as a fallback, but wherever the device has a haptic engine every event —
/// simple or not — plays a real Core Haptics `HapticSpec` instead. The first
/// build routed only the three "big" moments through Core Haptics and left
/// everything else as bare `hapticTransient` clicks at sharpness 0.7–0.9,
/// which is precisely the "cheap click" recipe: on a real phone it read as
/// tinny with no depth. Depth comes from a `hapticContinuous` body at low
/// sharpness (0.2–0.35) layered under a softer transient, so every event
/// below is built that way, however small.
///
/// Every call is safe to make from anywhere. If the device has no haptic
/// engine (iPad, Simulator) or the user has switched system haptics off, the
/// calls are inert rather than a crash or a stutter.
@MainActor
enum Haptics {

    // MARK: - Vocabulary

    /// `CaseIterable` so `HapticsLabView` can list every event without a
    /// second, hand-maintained list that would drift from this one.
    enum Event: CaseIterable, Hashable {
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
        // These three are meant to stay exactly as light/system as the
        // platform makes them — `UISelectionFeedbackGenerator` is already
        // the "light tick" Core Haptics would otherwise have to fake, and
        // routing them through a custom pattern only risks making them
        // heavier than they should be.
        case .scrubTick, .timerAdjusted, .selection:
            selectionChanged()
        // `.error` is a distinct, system-recognised shape; nothing built by
        // hand reads as clearly "that didn't work".
        case .failure:
            notification(.error)
        default:
            if !playSpec(currentSpec(for: event)) {
                fallback(for: event)
            }
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

    // MARK: - Simple generators (fallback path)

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

    /// The pre-Core-Haptics generator equivalents, used only when the engine
    /// can't play the real pattern (no engine, or `playSpec` threw). Kept
    /// close to the old numbers so a device without a Taptic Engine at all —
    /// which can't tell the difference anyway — still gets *something*.
    private static func fallback(for event: Event) {
        switch event {
        case .setCompleted:   impact(.light, intensity: 0.7)
        case .setUncompleted: impact(.soft, intensity: 0.5)
        case .setAdded:       impact(.light, intensity: 0.6)
        case .setDeleted:     impact(.rigid, intensity: 0.9)
        case .dropAdded:      impact(.medium, intensity: 0.7)
        case .swipeThreshold: impact(.rigid, intensity: 0.6)
        case .timerSkipped:   impact(.soft, intensity: 0.6)
        case .restComplete, .personalRecord, .celebration:
            notification(.success)
        case .scrubTick, .timerAdjusted, .selection, .failure:
            break // handled directly in `play(_:)`, never reaches here.
        }
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

    // MARK: - Core Haptics engine

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
    private static func playSpec(_ spec: HapticSpec) -> Bool {
        guard let engine, !spec.isEmpty else { return false }
        do {
            let pattern = try CHHapticPattern(events: spec.hapticEvents(), parameterCurves: spec.parameterCurves())
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Tuning surface (Haptics Lab)

    /// In-memory overrides set by `HapticsLabView`. Never persisted — the
    /// Lab is for a person holding the phone to feel their way to numbers
    /// and copy them out as text, not a user-facing setting, so an override
    /// dying on relaunch is the correct behaviour, not a bug.
    private static var overrides: [Event: HapticSpec] = [:]

    /// The spec currently in effect for `event` — the Lab's edit, if one has
    /// been made this session, otherwise the shipped default.
    static func currentSpec(for event: Event) -> HapticSpec {
        overrides[event] ?? baseSpec(for: event)
    }

    /// Live-applies an edited spec. The next `play(_:)` for this event picks
    /// it up immediately, which is what lets the Lab's sliders be felt in
    /// real time rather than requiring a separate "apply" step.
    static func override(_ spec: HapticSpec, for event: Event) {
        overrides[event] = spec
    }

    /// Drops every in-memory edit, returning all events to the shipped
    /// defaults from `baseSpec(for:)`.
    static func resetOverrides() {
        overrides.removeAll()
    }

    // MARK: - Default specs

    /// The shipped recipe for every event, expressed as `HapticSpec` rather
    /// than raw `CHHapticEvent`s so the exact same data the app plays is
    /// what the Lab edits and reads back — there is no second, parallel
    /// definition that could quietly drift from what's on a device.
    private static func baseSpec(for event: Event) -> HapticSpec {
        switch event {
        case .setCompleted:
            HapticSpec(transients: [.init(time: 0, intensity: 0.6, sharpness: 0.4)])

        case .setUncompleted:
            HapticSpec(transients: [.init(time: 0, intensity: 0.45, sharpness: 0.3)])

        case .setAdded:
            HapticSpec(transients: [.init(time: 0, intensity: 0.55, sharpness: 0.4)])

        case .setDeleted:
            // A short, low-sharpness body gives the delete some weight, with
            // a firmer transient near its end reading as the "snap" of the
            // row actually leaving — a bare click here felt identical to a
            // completed set, which is the wrong signal for something you
            // can't undo.
            HapticSpec(
                transients: [.init(time: 0.03, intensity: 0.6, sharpness: 0.45)],
                continuous: [.init(time: 0, duration: 0.09, intensity: 0.7, sharpness: 0.3)]
            )

        case .dropAdded:
            // Two soft transients 60ms apart, echoing the "chained onto a
            // parent" idea rather than reading as one more added set.
            HapticSpec(transients: [
                .init(time: 0, intensity: 0.55, sharpness: 0.4),
                .init(time: 0.06, intensity: 0.55, sharpness: 0.4)
            ])

        case .swipeThreshold:
            HapticSpec(transients: [.init(time: 0, intensity: 0.65, sharpness: 0.5)])

        case .timerSkipped:
            HapticSpec(continuous: [.init(time: 0, duration: 0.12, intensity: 0.5, sharpness: 0.25)])

        case .restComplete:
            // Body (low-sharpness continuous, decaying) + a sharper "strike"
            // transient partway through + a second, softer echo after it —
            // the ascending-chime shape the app relies on to read as "the
            // app is telling you something" rather than "you did something".
            HapticSpec(
                transients: [
                    .init(time: 0.12, intensity: 0.8, sharpness: 0.5),
                    .init(time: 0.26, intensity: 0.55, sharpness: 0.4)
                ],
                continuous: [
                    .init(time: 0, duration: 0.22, intensity: 0.7, sharpness: 0.2, curve: [
                        .init(relativeTime: 0, value: 1.0),
                        .init(relativeTime: 0.22, value: 0.4)
                    ])
                ]
            )

        case .personalRecord:
            // Longer and busier than anything else in the app on purpose: a
            // PR should feel like an event, and it can afford the time
            // because it interrupts nothing. A low body, two ascending
            // transients, then a rising swell at the end — the swell's
            // curve climbs rather than starting at full strength, so the
            // pattern still has somewhere to go in its last quarter-second.
            HapticSpec(
                transients: [
                    .init(time: 0.15, intensity: 0.9, sharpness: 0.4),
                    .init(time: 0.25, intensity: 0.7, sharpness: 0.35)
                ],
                continuous: [
                    .init(time: 0, duration: 0.4, intensity: 0.8, sharpness: 0.25),
                    .init(time: 0.5, duration: 0.22, intensity: 0.6, sharpness: 0.3, curve: [
                        .init(relativeTime: 0, value: 0.3),
                        .init(relativeTime: 0.22, value: 1.0)
                    ])
                ]
            )

        case .celebration:
            celebrationSpec()

        // Never routed through Core Haptics — see `play(_:)` — so there is
        // nothing to tune and the Lab shows these rows with no sliders.
        case .scrubTick, .timerAdjusted, .selection, .failure:
            HapticSpec()
        }
    }

    /// Scattered taps decaying over ~0.9s, matched to the confetti's fall
    /// rather than fired as one burst at the top. Each "hit" is now a pair —
    /// a transient plus a short, softer continuous tail — so it reads as a
    /// string of soft bursts rather than a string of clicks; a bare
    /// transient here at these intensities was the tinniest pattern in the
    /// app. The offsets are irregular on purpose — evenly spaced taps read
    /// as a machine.
    private static func celebrationSpec() -> HapticSpec {
        let offsets: [(TimeInterval, Float)] = [
            (0.00, 1.00), (0.07, 0.72), (0.13, 0.88), (0.22, 0.55),
            (0.31, 0.70), (0.42, 0.45), (0.55, 0.55), (0.71, 0.32),
            (0.90, 0.24)
        ]
        var transients: [HapticSpec.Transient] = []
        var continuous: [HapticSpec.Continuous] = []
        for (time, decay) in offsets {
            transients.append(.init(
                time: time,
                intensity: 0.35 + decay * 0.35,   // 0.35...0.70
                sharpness: 0.35 + decay * 0.15     // 0.35...0.50, never the sharper "click" range
            ))
            continuous.append(.init(
                time: time,
                duration: 0.06,
                intensity: max(0.2, decay * 0.4),
                sharpness: 0.25
            ))
        }
        return HapticSpec(transients: transients, continuous: continuous)
    }
}

// MARK: - HapticSpec

/// A haptic pattern as plain data — which events happen, how hard, how
/// textured, and when — instead of a hand-built `[CHHapticEvent]`. Every
/// pattern in `Haptics` is expressed as one of these so `HapticsLabView` can
/// read, edit, and replay the exact numbers that ship, with no risk of the
/// Lab's idea of a pattern drifting from the real one.
struct HapticSpec: Equatable {

    /// A single `.hapticTransient` — a click. Used alone, at high sharpness,
    /// this is the "cheap click" the research warns about; kept at sharpness
    /// 0.3–0.5 and layered under a continuous body, it reads as a strike
    /// instead.
    struct Transient: Identifiable, Equatable {
        let id: UUID
        var time: TimeInterval
        var intensity: Float
        var sharpness: Float

        init(id: UUID = UUID(), time: TimeInterval, intensity: Float, sharpness: Float) {
            self.id = id
            self.time = time
            self.intensity = intensity
            self.sharpness = sharpness
        }
    }

    /// A point on a `.hapticIntensityControl` parameter curve, relative to
    /// the start of the `Continuous` event it belongs to. Without a curve, a
    /// continuous event is a hard on/off block for its whole duration, which
    /// is its own flavour of tinny — a curve is what lets a body swell in or
    /// decay out instead of switching.
    struct CurvePoint: Equatable {
        var relativeTime: TimeInterval
        var value: Float
    }

    /// A single `.hapticContinuous` — the low-sharpness "body" that gives a
    /// pattern depth. Research (WWDC19 520, WWDC21 10278) puts the useful
    /// range at sharpness 0.2–0.35, intensity 0.6–0.8, for at least ~200ms.
    struct Continuous: Identifiable, Equatable {
        let id: UUID
        var time: TimeInterval
        var duration: TimeInterval
        var intensity: Float
        var sharpness: Float
        var curve: [CurvePoint]

        init(id: UUID = UUID(), time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float, curve: [CurvePoint] = []) {
            self.id = id
            self.time = time
            self.duration = duration
            self.intensity = intensity
            self.sharpness = sharpness
            self.curve = curve
        }
    }

    var transients: [Transient] = []
    var continuous: [Continuous] = []

    var isEmpty: Bool { transients.isEmpty && continuous.isEmpty }

    /// The flat `CHHapticEvent` list Core Haptics actually plays.
    func hapticEvents() -> [CHHapticEvent] {
        let transientEvents = transients.map {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: $0.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: $0.sharpness)
                ],
                relativeTime: $0.time
            )
        }
        let continuousEvents = continuous.map {
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: $0.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: $0.sharpness)
                ],
                relativeTime: $0.time,
                duration: $0.duration
            )
        }
        return transientEvents + continuousEvents
    }

    /// The intensity envelopes for any `Continuous` event that has curve
    /// points, so a body can swell or decay rather than switching on and off
    /// like a relay.
    func parameterCurves() -> [CHHapticParameterCurve] {
        continuous.compactMap { event in
            guard !event.curve.isEmpty else { return nil }
            let points = event.curve.map {
                CHHapticParameterCurve.ControlPoint(relativeTime: $0.relativeTime, value: $0.value)
            }
            return CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: points, relativeTime: event.time)
        }
    }

    /// A readable, Swift-literal-ish rendering of the numbers, for the
    /// Lab's "Copy values" action. This is the only path back from "tuned on
    /// a device" to "text a developer can paste into `baseSpec(for:)`" — the
    /// device is the one place these numbers can be judged, and this is how
    /// the judgment leaves the device.
    func exportText() -> String {
        var lines: [String] = []
        for transient in transients.sorted(by: { $0.time < $1.time }) {
            lines.append(String(
                format: "Transient(time: %.2f, intensity: %.2f, sharpness: %.2f)",
                transient.time, transient.intensity, transient.sharpness
            ))
        }
        for event in continuous.sorted(by: { $0.time < $1.time }) {
            var line = String(
                format: "Continuous(time: %.2f, duration: %.2f, intensity: %.2f, sharpness: %.2f",
                event.time, event.duration, event.intensity, event.sharpness
            )
            if !event.curve.isEmpty {
                let points = event.curve
                    .map { String(format: "(%.2f, %.2f)", $0.relativeTime, $0.value) }
                    .joined(separator: ", ")
                line += ", curve: [\(points)]"
            }
            line += ")"
            lines.append(line)
        }
        return lines.isEmpty ? "(plays through the system generator, not Core Haptics)" : lines.joined(separator: "\n")
    }
}
