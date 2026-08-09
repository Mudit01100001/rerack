import SwiftUI

/// Confetti burst from the top of the screen, for the finish flow (§9.4).
///
/// Uses `TimelineView(.animation)` so the body is re-evaluated every frame.
/// Two earlier approaches failed and are worth recording:
///
///   - `TimelineView(.animation(paused:))` — the schedule is captured when
///     the view is first built, so flipping `paused` later never restarts it.
///   - `withAnimation` on a single `progress` value — SwiftUI interpolates
///     the *endpoint* modifier values rather than re-running the per-piece
///     maths, and this effect's opacity is 0 at both ends (pieces start above
///     the screen and fade as they land). The confetti fell perfectly, fully
///     transparent, every time.
///
/// Respects Reduce Motion (§17): skipped entirely rather than slowed, because
/// slow confetti is worse for someone who asked for less motion than none.
struct ConfettiView: View {
    let isActive: Bool
    var pieceCount: Int = 80

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    private let duration: TimeInterval = 3.4

    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.36, blue: 0.35),
        Color(red: 0.99, green: 0.76, blue: 0.18),
        Color(red: 0.30, green: 0.78, blue: 0.47),
        Color(red: 0.29, green: 0.56, blue: 0.99),
        Color(red: 0.67, green: 0.43, blue: 0.93),
    ]

    private struct Piece {
        let xFraction: Double
        let delay: Double
        let drift: Double
        let spins: Double
        let width: Double
        let height: Double
        let color: Color
        let speed: Double
    }

    /// Fixed seed so the burst is identical on every one of the ~200 frames
    /// it's redrawn across — regenerating randomly per frame would make each
    /// piece teleport.
    private static let pieces: [Piece] = {
        var generator = SeededGenerator(seed: 20_260_809)
        return (0..<80).map { _ in
            Piece(
                xFraction: Double.random(in: 0...1, using: &generator),
                delay: Double.random(in: 0...0.35, using: &generator),
                drift: Double.random(in: -80...80, using: &generator),
                spins: Double.random(in: -3...3, using: &generator),
                width: Double.random(in: 6...11, using: &generator),
                height: Double.random(in: 10...17, using: &generator),
                color: palette.randomElement(using: &generator) ?? .blue,
                speed: Double.random(in: 0.8...1.3, using: &generator)
            )
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let startedAt {
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            let elapsed = timeline.date.timeIntervalSince(startedAt)
                            guard elapsed <= duration else { return }
                            for piece in Self.pieces {
                                draw(piece, elapsed: elapsed, size: size, into: &context)
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { fireIfNeeded() }
        .onChange(of: isActive) { _, _ in fireIfNeeded() }
    }

    private func draw(_ piece: Piece, elapsed: TimeInterval, size: CGSize, into context: inout GraphicsContext) {
        let local = (elapsed / duration - piece.delay) / max(1 - piece.delay, 0.01)
        guard local > 0, local <= 1 else { return }

        // Quadratic fall reads as gravity; linear reads as a lift.
        let y = -30 + local * local * piece.speed * (size.height + 90)
        let x = piece.xFraction * size.width + sin(local * 6) * piece.drift * local
        let opacity = local > 0.75 ? max(0, 1 - (local - 0.75) / 0.25) : 1

        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(local * piece.spins * .pi * 2))
        layer.fill(
            Path(
                roundedRect: CGRect(
                    x: -piece.width / 2,
                    y: -piece.height / 2,
                    width: piece.width,
                    height: piece.height
                ),
                cornerRadius: 1.5
            ),
            with: .color(piece.color)
        )
    }

    private func fireIfNeeded() {
        guard isActive, startedAt == nil, !reduceMotion else { return }
        startedAt = Date()
        // Tear the timeline down once the fall is over rather than leaving a
        // 60fps redraw running for the life of the screen.
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.2))
            startedAt = nil
        }
    }
}

/// Tiny LCG — enough to keep the burst stable across frames without a
/// dependency or reseeding the system generator globally.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
