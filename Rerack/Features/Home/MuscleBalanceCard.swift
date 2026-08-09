import SwiftUI

/// Which muscles have actually been trained lately, as a figure plus a ranked
/// list.
///
/// The figure is drawn from `Shape`s rather than an image asset: it has to
/// shade individual regions by volume, and a flat PNG can't do that. It's
/// also honest about resolution — a schematic obviously *is* a schematic,
/// where a detailed anatomical render would imply per-muscle precision the
/// data doesn't have (§23.1: primary-muscle attribution only, no weighting
/// across secondary muscles).
struct MuscleBalanceCard: View {
    let volumeByMuscle: [ProfileStats.MuscleVolume]
    var dayCount: Int = 30

    private var peak: Double { max(volumeByMuscle.first?.volumeKg ?? 0, 1) }

    private func share(_ muscles: [Muscle]) -> Double {
        let total = volumeByMuscle
            .filter { muscles.contains($0.muscle) }
            .reduce(0) { $0 + $1.volumeKg }
        return min(total / peak, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Muscle balance")
                    .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                Spacer()
                Text("Last \(dayCount) days")
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
            }

            if volumeByMuscle.isEmpty {
                Text("Log a few sessions and this fills in.")
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: DS.Space.md) {
                    BodySchematic(
                        chest: share([.chest]),
                        shoulders: share([.shouldersFront, .shouldersSide, .shouldersRear]),
                        arms: share([.biceps, .triceps, .forearms]),
                        back: share([.backLats, .backUpper, .lowerBack]),
                        core: share([.abs, .obliques]),
                        legs: share([.quads, .hamstrings, .glutes, .calves])
                    )
                    .frame(width: 92, height: 150)

                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(volumeByMuscle.prefix(5)) { entry in
                            HStack(spacing: DS.Space.xs) {
                                Text(entry.muscle.displayName)
                                    .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                                    .lineLimit(1)
                                    .frame(width: 92, alignment: .leading)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.08))
                                        Capsule()
                                            .fill(Color.accentColor)
                                            .frame(width: geometry.size.width * min(entry.volumeKg / peak, 1))
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(DS.Space.md)
        .dsCard()
    }
}

/// A deliberately schematic front-facing figure. Each region shades from the
/// share of volume it received.
private struct BodySchematic: View {
    let chest: Double
    let shoulders: Double
    let arms: Double
    let back: Double
    let core: Double
    let legs: Double

    private func fill(_ intensity: Double) -> Color {
        intensity <= 0.01
            ? Color.primary.opacity(0.10)
            : Color.accentColor.opacity(0.28 + 0.62 * intensity)
    }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {
                // Head — never shaded; there's no muscle group behind it, and
                // colouring it would imply data that doesn't exist.
                Circle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: w * 0.22, height: w * 0.22)
                    .position(x: w * 0.5, y: h * 0.08)

                // Shoulders
                Capsule()
                    .fill(fill(shoulders))
                    .frame(width: w * 0.62, height: h * 0.075)
                    .position(x: w * 0.5, y: h * 0.20)

                // Chest, with back shaded behind it as a wider band so a
                // pull-heavy week still reads as trained.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill(back))
                    .frame(width: w * 0.52, height: h * 0.16)
                    .position(x: w * 0.5, y: h * 0.30)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill(chest))
                    .frame(width: w * 0.40, height: h * 0.12)
                    .position(x: w * 0.5, y: h * 0.29)

                // Arms
                ForEach([0.16, 0.84], id: \.self) { x in
                    Capsule()
                        .fill(fill(arms))
                        .frame(width: w * 0.12, height: h * 0.26)
                        .position(x: w * x, y: h * 0.34)
                }

                // Core
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill(core))
                    .frame(width: w * 0.32, height: h * 0.13)
                    .position(x: w * 0.5, y: h * 0.46)

                // Legs
                ForEach([0.37, 0.63], id: \.self) { x in
                    Capsule()
                        .fill(fill(legs))
                        .frame(width: w * 0.18, height: h * 0.34)
                        .position(x: w * x, y: h * 0.74)
                }
            }
        }
        .accessibilityHidden(true) // the ranked list beside it carries the data
    }
}
