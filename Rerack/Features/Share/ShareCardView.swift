import SwiftUI

/// PRD §9.5. The renderable share card.
///
/// Built as a plain SwiftUI view so `ImageRenderer` can rasterise it at story
/// (1080×1920) or square (1080×1080) without a second code path. The
/// background is a gradient today and an `Image` the moment artwork exists —
/// `backgroundAssetName` is already threaded through, so swapping in a
/// designed background is dropping a file into the asset catalogue and
/// nothing else.
struct ShareCardView: View {
    enum Variant: String, CaseIterable, Identifiable {
        case animal, muscleMap, summary, stats
        var id: String { rawValue }

        var title: String {
            switch self {
            case .animal: "Animal"
            case .muscleMap: "Muscle Map"
            case .summary: "Full Summary"
            case .stats: "Stats"
            }
        }
    }

    enum Size {
        case story, square

        var pixels: CGSize {
            switch self {
            case .story: CGSize(width: 1080, height: 1920)
            case .square: CGSize(width: 1080, height: 1080)
            }
        }

        /// Rendered at 1/3 scale then upscaled by `ImageRenderer`, so layout
        /// maths stays in comfortable point values.
        var points: CGSize { CGSize(width: pixels.width / 3, height: pixels.height / 3) }
    }

    let variant: Variant
    let size: Size
    let content: ShareCardContent
    /// Set once designed backgrounds exist; falls back to the gradient.
    var backgroundAssetName: String?

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                Spacer(minLength: 12)
                bodyBlock
                Spacer(minLength: 12)
                footerBlock
            }
            .padding(size == .story ? 30 : 24)
        }
        .frame(width: size.points.width, height: size.points.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let backgroundAssetName, UIImage(named: backgroundAssetName) != nil {
            Image(backgroundAssetName)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.35)) // keeps text legible over any art
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.13),
                    Color(red: 0.13, green: 0.16, blue: 0.30),
                    Color(red: 0.30, green: 0.18, blue: 0.36),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Blocks

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(content.workoutTitle.uppercased())
                .font(.system(size: size == .story ? 15 : 13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.65))
            Text(content.dateLine)
                .font(.system(size: size == .story ? 12 : 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bodyBlock: some View {
        switch variant {
        case .animal: animalBody
        case .muscleMap: muscleMapBody
        case .summary: summaryBody
        case .stats: statsBody
        }
    }

    /// §9.5.1. The silhouette slot renders a glyph until artwork lands; the
    /// numbers and the progress line are already real.
    private var animalBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let asset = content.animalAssetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: size == .story ? 74 : 60))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(height: size == .story ? 130 : 100)

            Text("\(content.volumeFormatted) lifted")
                .font(.system(size: size == .story ? 30 : 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let comparison = content.animalComparison {
                Text(comparison)
                    .font(.system(size: size == .story ? 17 : 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let progress = content.animalProgress {
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.2))
                            Capsule()
                                .fill(.white)
                                .frame(width: geometry.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 7)
                    Text(progress.label)
                        .font(.system(size: size == .story ? 12 : 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// §9.5 variant 2. The figure is a placeholder until MuscleMap (or
    /// artwork) lands; the ranked volume-by-muscle list underneath is real
    /// data and carries the card on its own meanwhile.
    private var muscleMapBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: size == .story ? 90 : 72))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)

            ForEach(content.muscleBreakdown.prefix(4), id: \.name) { entry in
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: size == .story ? 13 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(.white.opacity(0.85))
                                .frame(width: geometry.size.width * entry.fraction)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(content.exerciseLines.prefix(size == .story ? 9 : 6), id: \.self) { line in
                Text(line)
                    .font(.system(size: size == .story ? 13 : 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            if content.exerciseLines.count > (size == .story ? 9 : 6) {
                Text("+ \(content.exerciseLines.count - (size == .story ? 9 : 6)) more")
                    .font(.system(size: size == .story ? 12 : 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsBody: some View {
        VStack(alignment: .leading, spacing: size == .story ? 14 : 10) {
            statLine(content.durationFormatted, "Duration")
            statLine(content.volumeFormatted, "Volume")
            statLine("\(content.setCount)", "Sets")
            if content.prCount > 0 {
                statLine("\(content.prCount)", content.prCount == 1 ? "Record" : "Records")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLine(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: size == .story ? 33 : 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: size == .story ? 11 : 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var footerBlock: some View {
        HStack {
            Text(AppIdentity.displayName)
                .font(.system(size: size == .story ? 15 : 13, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if let username = content.username, !username.isEmpty {
                Text("@\(username)")
                    .font(.system(size: size == .story ? 13 : 12))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

/// Everything a card renders, resolved once from the workout so no card
/// variant touches SwiftData or recomputes a total differently from another.
struct ShareCardContent {
    struct MuscleEntry {
        let name: String
        /// 0…1 against the hardest-hit muscle in the session.
        let fraction: Double
    }

    struct AnimalProgress {
        let fraction: Double
        let label: String
    }

    let workoutTitle: String
    let dateLine: String
    let durationFormatted: String
    /// Pre-formatted *with* its unit. `ImageRenderer` draws this view outside
    /// the view hierarchy, so `@Environment` never reaches it — anything the
    /// card needs has to arrive as plain data or it silently renders the
    /// default.
    let volumeFormatted: String
    let setCount: Int
    let prCount: Int
    let exerciseLines: [String]
    let muscleBreakdown: [MuscleEntry]
    let animalComparison: String?
    let animalProgress: AnimalProgress?
    let animalAssetName: String?
    let username: String?
}
