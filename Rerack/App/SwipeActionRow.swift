import SwiftUI

/// Mail-style swipe actions for rows that are **not** in a `List`.
///
/// `.swipeActions` is honoured by `List` alone. The active workout screen is a
/// `ScrollView` of cards — chosen so the exercise cards, banding and
/// concentric radii are possible at all — so every `.swipeActions` declared on
/// a set row was silently inert. `+ Drop` and swipe-to-delete therefore did
/// not exist at runtime despite both being written, spec'd, and marked built.
///
/// This reimplements the interaction rather than reshaping the screen around
/// `List`, because drop rows have to be independently swipeable while still
/// sharing their parent's alternating band — a nesting that a flat list of
/// rows cannot express.
///
/// What it deliberately reproduces from the system behaviour:
/// - the row tracks the finger, with rubber-banding past the action width
/// - a detent haptic the moment a release would commit
/// - full-swipe to fire the first action without lifting
/// - opening one row closes any other, app-wide
/// - VoiceOver reaches every action through the rotor, since a bare
///   `DragGesture` is invisible to it
struct SwipeAction: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let tint: Color
    /// Destructive actions get the full-swipe slot and a firmer haptic.
    let isDestructive: Bool
    let action: () -> Void

    init(
        label: String,
        systemImage: String,
        tint: Color,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// Tracks which row is open so that swiping a second row closes the first,
/// matching Mail. Without this, several rows sit open at once and the screen
/// reads as broken.
@Observable
@MainActor
final class SwipeRowCoordinator {
    var openRowID: UUID?
    func close() { openRowID = nil }
}

private struct SwipeRowCoordinatorKey: EnvironmentKey {
    @MainActor static let defaultValue = SwipeRowCoordinator()
}

extension EnvironmentValues {
    var swipeRowCoordinator: SwipeRowCoordinator {
        get { self[SwipeRowCoordinatorKey.self] }
        set { self[SwipeRowCoordinatorKey.self] = newValue }
    }
}

struct SwipeActionRow<Content: View>: View {
    var leading: [SwipeAction] = []
    var trailing: [SwipeAction] = []
    @ViewBuilder var content: () -> Content

    @Environment(\.swipeRowCoordinator) private var coordinator
    @State private var rowID = UUID()
    @State private var offset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0
    @State private var hasCrossedThreshold = false

    /// Build 5 item B: iOS 26 Mail's swipe-action geometry, read off the
    /// reference the user supplied — a 44pt filled circle per action, 16pt
    /// between circles, the whole group inset 12pt from the row's edge.
    /// `actionWidth` is that per-action footprint; a side's fully-open offset
    /// is `count × actionWidth + edgeInset`. This replaces the old iOS-7-era
    /// full-height coloured strip entirely.
    private let circleDiameter: CGFloat = 44
    private let circleSpacing: CGFloat = 16
    private let edgeInset: CGFloat = 12
    private var actionWidth: CGFloat { circleDiameter + circleSpacing }
    /// Past this fraction of the revealed width, releasing commits instead of
    /// snapping open.
    private let fullSwipeFraction: CGFloat = 1.6

    private func revealWidth(for actions: [SwipeAction]) -> CGFloat {
        guard !actions.isEmpty else { return 0 }
        return CGFloat(actions.count) * actionWidth + edgeInset
    }

    private var leadingWidth: CGFloat { revealWidth(for: leading) }
    private var trailingWidth: CGFloat { revealWidth(for: trailing) }

    var body: some View {
        ZStack {
            actionLayer
            content()
                .background(
                    // The content needs an opaque backing or the action
                    // circles show through the row as it slides.
                    Color(.secondarySystemGroupedBackground)
                        .opacity(offset == 0 ? 0 : 1)
                )
                .offset(x: offset)
                .background(
                    // A SwiftUI `DragGesture` here is swallowed by the row's
                    // `TextField`s: verified on device, the swipe fired from
                    // the set-number column and did nothing when begun on the
                    // kg or reps field, which is most of the row's width. The
                    // fields' own UIKit recognizers win the arena before a
                    // parent `simultaneousGesture` ever sees the touch.
                    SwipeGestureCatcher(
                        rowID: rowID,
                        onChanged: { handleDragChanged($0) },
                        onEnded: { translation, velocity in
                            handleDragEnded(translation: translation, velocity: velocity)
                        }
                    )
                )
        }
        .clipped()
        .onAppear {
            // Idempotent: every row sets the same closure on the shared hub.
            let coordinator = self.coordinator
            SwipeGestureHub.shared.onScrollBegan = { coordinator.close() }
        }
        .onChange(of: coordinator.openRowID) { _, newValue in
            guard newValue != rowID, offset != 0 else { return }
            close()
        }
        .accessibilityActions {
            // A DragGesture is invisible to VoiceOver. Without these, every
            // action behind a swipe would be unreachable with the screen
            // reader on — which is how §17's accessibility requirement would
            // have quietly been violated by the fix for a bug.
            ForEach(leading + trailing) { action in
                Button(action.label) {
                    close()
                    action.action()
                }
            }
        }
    }

    // MARK: - Revealed actions

    private var actionLayer: some View {
        HStack(spacing: 0) {
            if !leading.isEmpty {
                actionStack(leading, revealed: max(offset, 0), width: leadingWidth, insetEdge: .leading)
            }
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                actionStack(trailing, revealed: max(-offset, 0), width: trailingWidth, insetEdge: .trailing)
            }
        }
    }

    /// iOS 26 Mail draws each action as a filled circle with its label
    /// underneath, *outside* the circle, rather than an icon-over-label pill
    /// filling a coloured strip. Nothing here paints a background behind the
    /// `HStack` itself — the circles float directly on whatever the row sits
    /// on, and only the content layer in `body` carries an opaque background,
    /// so the row visibly slides over them rather than the circles sliding
    /// out from underneath a strip.
    private func actionStack(
        _ actions: [SwipeAction],
        revealed: CGFloat,
        width: CGFloat,
        insetEdge: Edge.Set
    ) -> some View {
        let progress = width > 0 ? min(revealed / width, 1) : 0
        return HStack(spacing: circleSpacing) {
            ForEach(actions) { action in
                Button {
                    fire(action)
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(action.tint)
                            .frame(width: circleDiameter, height: circleDiameter)
                            .overlay {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        Text(action.label)
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(insetEdge, edgeInset)
        // Grows in from a slightly shrunk, transparent state rather than
        // appearing fully formed the instant the row starts moving — the
        // same "materialising" feel the reference's own reveal has.
        .scaleEffect(0.6 + 0.4 * progress)
        .opacity(progress)
    }

    // MARK: - Gesture

    private func handleDragChanged(_ translation: CGFloat) {
        if coordinator.openRowID != rowID { coordinator.openRowID = rowID }

        let proposed = settledOffset + translation
        offset = rubberBanded(proposed)

        let limit = proposed > 0 ? leadingWidth : trailingWidth
        let crossed = limit > 0 && abs(proposed) > limit * fullSwipeFraction
        if crossed != hasCrossedThreshold {
            hasCrossedThreshold = crossed
            if crossed { Haptics.play(.swipeThreshold) }
        }
    }

    private func handleDragEnded(translation: CGFloat, velocity: CGFloat) {
        hasCrossedThreshold = false
        // Velocity matters as much as distance: a short fast flick should
        // open, a long slow drag that stops early should not.
        let projected = settledOffset + translation + velocity * 0.12

        if projected > 0, !leading.isEmpty {
            resolve(projected: projected, width: leadingWidth, actions: leading, sign: 1)
        } else if projected < 0, !trailing.isEmpty {
            resolve(projected: -projected, width: trailingWidth, actions: trailing, sign: -1)
        } else {
            close()
        }
    }

    private func resolve(projected: CGFloat, width: CGFloat, actions: [SwipeAction], sign: CGFloat) {
        if projected > width * fullSwipeFraction {
            // Full swipe fires the destructive action if there is one, else
            // the outermost — same precedence Mail uses.
            let action = actions.first(where: \.isDestructive) ?? actions[0]
            fire(action)
        } else if projected > width * 0.5 {
            withAnimation(.snappy(duration: 0.25)) {
                offset = width * sign
                settledOffset = width * sign
            }
        } else {
            close()
        }
    }

    /// Past the natural width the row keeps moving, but at a third of the
    /// distance. Without this the row hits a hard wall and the gesture feels
    /// like it broke rather than reached its end.
    private func rubberBanded(_ proposed: CGFloat) -> CGFloat {
        let limit = proposed > 0 ? leadingWidth : trailingWidth
        guard limit > 0 else { return 0 }
        let magnitude = abs(proposed)
        guard magnitude > limit else { return proposed }
        let overshoot = magnitude - limit
        return (limit + overshoot / 3) * (proposed > 0 ? 1 : -1)
    }

    private func fire(_ action: SwipeAction) {
        Haptics.play(action.isDestructive ? .setDeleted : .setAdded)
        close()
        action.action()
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) {
            offset = 0
            settledOffset = 0
        }
        if coordinator.openRowID == rowID { coordinator.openRowID = nil }
    }
}


// MARK: - UIKit pan catcher

/// Gives `SwipeGestureHub` a view whose frame describes where this row is,
/// and registers/unregisters this row with it.
///
/// Attaching to the scroll view rather than to the row is deliberate — see
/// the hub's own header comment. A recognizer added to the row's own backing
/// view sits *below* the text fields in the responder chain and loses to
/// them; one on the shared ancestor sees every touch, and the hub's
/// `gestureRecognizerShouldBegin` filters it back down to "horizontal, and
/// inside this row's bounds."
private struct SwipeGestureCatcher: UIViewRepresentable {
    let rowID: UUID
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        SwipeGestureHub.shared.register(id: rowID, markerView: view, onChanged: onChanged, onEnded: onEnded)
        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        // An upsert, not a one-time registration: SwiftUI calls this on
        // every re-render, and the closures captured here close over this
        // render's `offset`/`settledOffset` — the hub needs the *current*
        // ones, not whichever were current when the row first appeared.
        SwipeGestureHub.shared.register(id: rowID, markerView: uiView, onChanged: onChanged, onEnded: onEnded)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rowID: rowID)
    }

    /// The other half of `register`, and the actual fix for the leak: called
    /// the moment SwiftUI tears this row's representable down, so a
    /// scrolled-away, recycled, or deleted row can never again be routed a
    /// touch that lands where it used to be.
    static func dismantleUIView(_ uiView: PassthroughView, coordinator: Coordinator) {
        SwipeGestureHub.shared.unregister(id: coordinator.rowID)
    }

    /// Never a hit-test target, so it cannot steal a tap from the row it
    /// covers — it exists only to give the hub a view whose frame describes
    /// where this row is.
    final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    /// Carries the identity `dismantleUIView` unregisters, and gives `deinit`
    /// a second, independent unregister path — SwiftUI doesn't promise
    /// `dismantleUIView` and the coordinator's deallocation land in the same
    /// runloop turn, and a row left registered in the gap between them could
    /// still catch a touch that belongs to nothing on screen any more.
    @MainActor
    final class Coordinator {
        let rowID: UUID

        init(rowID: UUID) {
            self.rowID = rowID
        }

        deinit {
            // `deinit` isn't guaranteed to run on the main actor, so the
            // MainActor-isolated unregister has to be hopped to rather than
            // called directly. Only a plain `UUID` value crosses that hop —
            // never `self`, which is already being torn down.
            let id = rowID
            Task { @MainActor in
                SwipeGestureHub.shared.unregister(id: id)
            }
        }
    }
}

/// The single `UIPanGestureRecognizer` every swipeable row shares.
///
/// Previously, every row installed its own `UIPanGestureRecognizer` directly
/// on the shared `UIScrollView` and never removed it: a 6-exercise session
/// put roughly two dozen recognizers on one scroll view, all evaluated on
/// every touch, and they kept accumulating as rows recycled during scrolling
/// — which is what made scrolling itself feel janky, not just the swipe
/// gesture. This hub installs exactly one recognizer, the first time any row
/// asks for it, and keeps a registry of `(rowID, weak markerView, onChanged,
/// onEnded)` it can route a gesture to. `gestureRecognizerShouldBegin` picks
/// the one row whose marker view contains the touch's start location and
/// claims the gesture for that row until it ends — so a single diagonal drag
/// can't hand off between rows mid-gesture.
@MainActor
final class SwipeGestureHub: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeGestureHub()

    /// Fired when the hub sees a touch on the scroll view that is *not* a
    /// horizontal swipe — a scroll, a tap into a field. The row coordinator
    /// uses it to close whichever row is open.
    var onScrollBegan: (() -> Void)?

    private final class Entry {
        weak var markerView: UIView?
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void
        init(markerView: UIView, onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.markerView = markerView
            self.onChanged = onChanged
            self.onEnded = onEnded
        }
    }

    private var entries: [UUID: Entry] = [:]
    private weak var installedOn: UIScrollView?
    /// The row currently owning an in-flight gesture, set the moment
    /// `gestureRecognizerShouldBegin` picks a winner and held until the
    /// gesture ends — every `.changed` in between routes here rather than
    /// re-hit-testing on each move.
    private var activeID: UUID?

    private override init() { super.init() }

    /// An upsert, not a plain add — see `updateUIView`'s comment for why
    /// registering more than once is expected and harmless.
    func register(
        id: UUID,
        markerView: UIView,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat, CGFloat) -> Void
    ) {
        entries[id] = Entry(markerView: markerView, onChanged: onChanged, onEnded: onEnded)
        installIfNeeded(startingFrom: markerView)
    }

    func unregister(id: UUID) {
        entries.removeValue(forKey: id)
        if activeID == id { activeID = nil }
    }

    /// The marker view isn't in a window yet the first time any row
    /// registers, so the scroll view can't always be found on the first try.
    /// Retried a handful of times rather than once — a single hop is enough
    /// on a warm launch and not enough on a cold one.
    private func installIfNeeded(startingFrom markerView: UIView, attempt: Int = 0) {
        guard installedOn == nil else { return }
        guard let scrollView = Self.enclosingScrollView(of: markerView) else {
            guard attempt < 6 else { return }
            Task { @MainActor [weak self, weak markerView] in
                guard let self, let markerView else { return }
                self.installIfNeeded(startingFrom: markerView, attempt: attempt + 1)
            }
            return
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        scrollView.addGestureRecognizer(pan)
        installedOn = scrollView
    }

    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var candidate: UIView? = view.superview
        while let current = candidate, !(current is UIScrollView) {
            candidate = current.superview
        }
        return candidate as? UIScrollView
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let activeID, let entry = entries[activeID] else { return }
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed:
            entry.onChanged(translation)
        case .ended, .cancelled, .failed:
            entry.onEnded(translation, pan.velocity(in: pan.view).x)
            self.activeID = nil
        default:
            break
        }
    }

    /// The one arbiter for the whole scroll view: the pan has to be
    /// decisively horizontal, and its start location has to fall inside
    /// exactly one registered row's marker view.
    nonisolated func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let pan = recognizer as? UIPanGestureRecognizer, let scrollView = pan.view else { return false }
            let velocity = pan.velocity(in: scrollView)
            // 1.5x rather than a plain comparison: a mostly-vertical drag
            // with a little sideways drift is a scroll, not a swipe.
            guard abs(velocity.x) > abs(velocity.y) * 1.5 else {
                // A scroll has begun. Mail closes any open row the moment
                // you scroll or touch anywhere else, and a row left hanging
                // open while the list moves under it reads as broken — so
                // the hub, which sees every touch on the scroll view, is
                // the one place that can close it reliably.
                onScrollBegan?()
                return false
            }
            let touch = pan.location(in: scrollView)
            for (id, entry) in entries {
                guard let markerView = entry.markerView else { continue }
                let local = markerView.convert(touch, from: scrollView)
                if markerView.bounds.contains(local) {
                    activeID = id
                    return true
                }
            }
            return false
        }
    }

    nonisolated func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
