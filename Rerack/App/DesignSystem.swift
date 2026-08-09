import SwiftUI

/// One place for the values that were previously guessed per-view: corner
/// radii, spacing, and the type scale. Every literal `cornerRadius: 12` and
/// `.font(.headline)` scattered across the app was an independent decision,
/// which is why the radii disagreed and the type looked unrelated.
enum DS {

    // MARK: - Corner radii

    /// Apple has used `.continuous` (squircle) corners since iOS 7 — the
    /// system's own cards, sheets and controls all use them. A circular
    /// `cornerRadius` is the single strongest "this was built in 2014" tell,
    /// so every rounded rect in the app goes through these.
    enum Radius {
        /// Inputs, chips, small tags.
        static let small: CGFloat = 10
        /// Containers nested *inside* a card.
        static let medium: CGFloat = 14
        /// Top-level cards.
        static let large: CGFloat = 20
        /// Sheets and full-width hero surfaces.
        static let xlarge: CGFloat = 26
    }

    /// Nested corners look wrong when parent and child share a radius — the
    /// gap between them reads as uneven. Concentric radii keep the curves
    /// parallel: inner = outer − padding.
    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 4)
    }

    // MARK: - Spacing

    /// A 4pt grid. Everything in the app snaps to it, so vertical rhythm is
    /// consistent without anyone eyeballing an 11 next to a 13.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: - Type scale

    /// Golden-ratio modular scale, anchored on iOS's 17pt body.
    ///
    /// φ = 1.618. Whole φ steps alone give only 10.5 / 17 / 27.5 — three
    /// sizes, which isn't enough to build a UI, and the jump from body to
    /// title is violent. So the scale also uses **√φ = 1.272** as the half
    /// step; every size is still φ-derived, just at half-octaves.
    ///
    ///     caption2  17 / φ        = 10.5
    ///     caption   17 / √φ       = 13.4
    ///     body      17            = 17.0
    ///     heading   17 × √φ       = 21.6
    ///     title     17 × φ        = 27.5
    ///     display   17 × φ × √φ   = 35.0
    ///
    /// **These are base sizes, not fixed ones.** They're applied through
    /// `@ScaledMetric` so they still grow with Dynamic Type — §17 requires
    /// legibility to XXL, and a hardcoded `.system(size:)` would silently
    /// break that for every accessibility user.
    enum TypeScale {
        static let phi: CGFloat = 1.618
        static let halfPhi: CGFloat = 1.272 // √φ

        static let caption2: CGFloat = 10.5
        static let caption: CGFloat = 13.4
        static let body: CGFloat = 17.0
        static let heading: CGFloat = 21.6
        static let title: CGFloat = 27.5
        static let display: CGFloat = 35.0
    }
}

/// Applies a `DS.TypeScale` size that still honours Dynamic Type.
///
/// `.font(.system(size:))` in SwiftUI does **not** scale with the user's text
/// size — it's a fixed point value. `@ScaledMetric` re-derives the size from
/// the current content-size category, so a golden-ratio scale and an
/// accessibility-legible one stop being mutually exclusive.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `relativeTo` decides which Dynamic Type curve the size follows —
    /// headings and body text scale at different rates, and matching the
    /// nearest system style keeps that behaviour.
    func dsFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFont(size: size, relativeTo: textStyle, weight: weight, design: design))
    }
}

// MARK: - Shared shapes

extension View {
    /// Card surface: continuous corners, a hairline border instead of a drop
    /// shadow. Borders read cleaner than shadows in both light and dark, and
    /// don't stack visually when cards sit next to each other.
    func dsCard(radius: CGFloat = DS.Radius.large) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}
