import Foundation

/// PRD §9.5.1. Maps session volume onto a reference animal, plus progress
/// toward the next one up.
///
/// Pure maths, no artwork: `assetName` is derived from the animal's name so a
/// silhouette can be dropped into the asset catalogue later and picked up
/// with no code change.
enum AnimalLadder {
    struct Animal {
        let name: String
        let kg: Double
        let emoji: String
        var assetName: String { ExerciseArtwork.animalAssetName(for: name) }
    }

    /// §9.5.1's table, ascending.
    static let anchors: [Animal] = [
        Animal(name: "House cat", kg: 4.5, emoji: "🐈"),
        Animal(name: "Bulldog", kg: 25, emoji: "🐕"),
        Animal(name: "Cheetah", kg: 60, emoji: "🐆"),
        Animal(name: "Panda", kg: 110, emoji: "🐼"),
        Animal(name: "Lion", kg: 190, emoji: "🦁"),
        Animal(name: "Grizzly bear", kg: 400, emoji: "🐻"),
        Animal(name: "Polar bear", kg: 450, emoji: "🐻‍❄️"),
        Animal(name: "Horse", kg: 500, emoji: "🐴"),
        Animal(name: "Bison", kg: 900, emoji: "🦬"),
        Animal(name: "Giraffe", kg: 1_200, emoji: "🦒"),
        Animal(name: "Rhinoceros", kg: 2_300, emoji: "🦏"),
        Animal(name: "Hippopotamus", kg: 3_000, emoji: "🦛"),
        Animal(name: "Orca", kg: 5_400, emoji: "🐋"),
        Animal(name: "African elephant", kg: 6_000, emoji: "🐘"),
        Animal(name: "Humpback whale", kg: 30_000, emoji: "🐳"),
        Animal(name: "Blue whale", kg: 150_000, emoji: "🐋"),
    ]

    struct Match {
        let animal: Animal
        /// e.g. `1.4` — how many of this animal the volume comes to.
        let multiple: Double
        /// nil once the top of the ladder is reached.
        let next: Animal?
        /// 0…1 toward `next`.
        let progressToNext: Double

        /// `1.4 × Horse 🐴`, or `28% of a House cat 🐈` below the ladder's
        /// floor — §9.5.1 step 3.
        var headline: String {
            if multiple < 1 {
                return "\(Int((multiple * 100).rounded()))% of a \(animal.name) \(animal.emoji)"
            }
            return String(format: "%.1f × %@ %@", multiple, animal.name, animal.emoji)
        }

        var progressLabel: String? {
            guard let next else { return nil }
            return "\(Int((progressToNext * 100).rounded()))% of the way to \(articled(next.name)) \(next.emoji)"
        }

        private func articled(_ name: String) -> String {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let article = name.first.map { vowels.contains(Character($0.lowercased())) ? "an" : "a" } ?? "a"
            return "\(article) \(name)"
        }
    }

    /// §9.5.1 step 2: pick the anchor where `volume / anchor` lands in 1.0–3.0;
    /// among ties take the heaviest. Below the lightest anchor, express as a
    /// percentage of it rather than inventing a smaller animal.
    static func match(volumeKg: Double) -> Match? {
        guard volumeKg > 0, let lightest = anchors.first else { return nil }

        guard volumeKg >= lightest.kg else {
            return Match(
                animal: lightest,
                multiple: volumeKg / lightest.kg,
                next: anchors.dropFirst().first,
                progressToNext: min(volumeKg / lightest.kg, 1)
            )
        }

        // Heaviest anchor in the 1.0–3.0 band; falls back to the heaviest
        // anchor at or below the volume when nothing lands in band (the gaps
        // between whale-scale anchors are wider than 3×).
        let inBand = anchors.filter { anchor in
            let multiple = volumeKg / anchor.kg
            return multiple >= 1 && multiple <= 3
        }
        let chosen = inBand.last ?? anchors.last { volumeKg >= $0.kg } ?? lightest
        let next = anchors.first { $0.kg > chosen.kg }

        let progress: Double
        if let next {
            // Measured from the chosen anchor to the next, not from zero —
            // otherwise every card past the first anchor reads ~99%.
            progress = min(max((volumeKg - chosen.kg) / (next.kg - chosen.kg), 0), 1)
        } else {
            progress = 1
        }

        return Match(
            animal: chosen,
            multiple: volumeKg / chosen.kg,
            next: next,
            progressToNext: progress
        )
    }
}
