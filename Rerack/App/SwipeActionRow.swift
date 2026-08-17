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

    /// Wide enough for a 20pt glyph plus breathing room on each side, and
    /// comfortably past the 44pt minimum touch target.
    private let actionWidth: CGFloat = 74
    /// Past this fraction of the revealed width, releasing commits instead of
    /// snapping open.
    private let fullSwipeFraction: CGFloat = 1.6

    private var leadingWidth: CGFloat { CGFloat(leading.count) * actionWidth }
    private var trailingWidth: CGFloat { CGFloat(trailing.count) * actionWidth }

    var body: some View {
        ZStack {
            actionLayer
            content()
                .background(
                    // The content needs an opaque backing or the action
                    // buttons show through the row as it slides.
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
                        onChanged: { handleDragChanged($0) },
                        onEnded: { translation, velocity in
                            handleDragEnded(translation: translation, velocity: velocity)
                        }
                    )
                )
        }
        .clipped()
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
                actionStack(leading, revealed: max(offset, 0))
            }
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                actionStack(trailing, revealed: max(-offset, 0))
            }
        }
    }

    private func actionStack(_ actions: [SwipeAction], revealed: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    fire(action)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(action.label)
                            .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                }
                .buttonStyle(.plain)
            }
        }
        // Fading the buttons in as the row moves stops them appearing fully
        // formed under a row that has barely shifted.
        .opacity(Double(min(revealed / actionWidth, 1)))
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

/// Installs a `UIPanGestureRecognizer` on the enclosing scroll view and gates
/// it to horizontal movement that started inside this row.
///
/// Attaching to the scroll view rather than to the row is deliberate. A
/// recognizer added to the row's own backing view sits *below* the text
/// fields in the responder chain and loses to them; one on the shared
/// ancestor sees every touch, and `gestureRecognizerShouldBegin` filters it
/// back down to "horizontal, and inside my bounds."
///
/// Vertical scrolling is untouched because the recognizer refuses to begin
/// unless the pan is decisively horizontal, and it declares simultaneous
/// recognition so taps still reach the field underneath.
private struct SwipeGestureCatcher: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        context.coordinator.rowView = view
        context.coordinator.scheduleInstall()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.scheduleInstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    /// Never a hit-test target, so it cannot steal a tap from the row it
    /// covers — it exists only to give the coordinator a view whose frame
    /// describes where this row is.
    final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void
        weak var rowView: UIView?
        private weak var installedOn: UIView?
        private var installAttempts = 0

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        /// The view is not in a window yet when `makeUIView` runs, so the
        /// scroll view cannot be found on the first pass. Retry a handful of
        /// times rather than once — a single `async` hop is enough on a warm
        /// launch and not enough on a cold one.
        func scheduleInstall() {
            guard installedOn == nil, installAttempts < 6 else { return }
            installAttempts += 1
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.install() == false { self.scheduleInstall() }
            }
        }

        private func install() -> Bool {
            guard installedOn == nil, let rowView else { return true }
            var candidate: UIView? = rowView.superview
            while let view = candidate, !(view is UIScrollView) {
                candidate = view.superview
            }
            guard let scrollView = candidate else { return false }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
            installedOn = scrollView
            return true
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view).x
            switch pan.state {
            case .changed:
                onChanged(translation)
            case .ended, .cancelled, .failed:
                onEnded(translation, pan.velocity(in: pan.view).x)
            default:
                break
            }
        }

        nonisolated func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated {
                guard let pan = recognizer as? UIPanGestureRecognizer, let rowView else { return false }
                let velocity = pan.velocity(in: pan.view)
                // 1.5x rather than a plain comparison: a mostly-vertical drag
                // with a little sideways drift is a scroll, not a swipe.
                guard abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
                let location = pan.location(in: rowView)
                return rowView.bounds.contains(location)
            }
        }

        nonisolated func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
