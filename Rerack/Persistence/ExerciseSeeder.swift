import Foundation
import SwiftData

/// Mirrors the JSON shape of Resources/ExerciseCatalog.json. Field names
/// match the enum raw values in Enums.swift exactly (camelCase case names).
private struct ExerciseSeed: Decodable {
    let name: String
    let equipment: Equipment
    let primaryMuscle: Muscle
    let secondaryMuscles: [Muscle]
    let loadType: LoadType
    let bodyweightFactor: Double
    let defaultRestSeconds: Int?
    let catalogVersion: Int
    /// Absent for entries free-exercise-db has no match for; decoded as empty.
    let instructions: [String]?
}

/// PRD §9.1: "bundled JSON seed file, loaded into the DB on first launch,
/// versioned so future app updates can add exercises without duplicating."
///
/// Each entry in the catalogue JSON carries the `catalogVersion` of the app
/// release that introduced it. The seeder tracks the highest version it has
/// already applied and only inserts rows newer than that — so bumping the
/// bundled file in a future update to add exercises is additive, never a
/// re-insert of everything that's already there.
enum ExerciseSeeder {
    private static let lastAppliedVersionKey = "com.mudit.logbook.exerciseCatalogVersion"

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "ExerciseCatalog", withExtension: "json") else {
            assertionFailure("ExerciseCatalog.json is missing from the app bundle")
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            assertionFailure("ExerciseCatalog.json could not be read")
            return
        }

        guard let seeds = try? JSONDecoder().decode([ExerciseSeed].self, from: data) else {
            assertionFailure("ExerciseCatalog.json failed to decode, check enum raw values match Enums.swift")
            return
        }

        let lastApplied = UserDefaults.standard.integer(forKey: lastAppliedVersionKey)
        let newSeeds = seeds.filter { $0.catalogVersion > lastApplied }

        // Backfill before inserting. The version gate only decides what's
        // *new*; it can't carry a field that was added to rows that already
        // exist. Instructions arrived at M11 for entries seeded at v1, so an
        // existing install would otherwise keep an empty How To tab forever.
        //
        // Only fills blanks — never overwrites, so a custom edit survives.
        backfillInstructions(from: seeds, context: context)

        guard !newSeeds.isEmpty else {
            try? context.save()
            return
        }

        for seed in newSeeds {
            let exercise = Exercise(
                name: seed.name,
                equipment: seed.equipment,
                primaryMuscle: seed.primaryMuscle,
                secondaryMuscles: seed.secondaryMuscles,
                loadType: seed.loadType,
                bodyweightFactor: seed.bodyweightFactor,
                isCustom: false,
                defaultRestSeconds: seed.defaultRestSeconds,
                catalogVersion: seed.catalogVersion,
                instructions: seed.instructions ?? []
            )
            context.insert(exercise)
        }

        let highestApplied = newSeeds.map(\.catalogVersion).max() ?? lastApplied
        UserDefaults.standard.set(highestApplied, forKey: lastAppliedVersionKey)

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save seeded exercise catalogue: \(error)")
        }
    }

    /// Fills in `instructions` on catalogue rows that predate the field.
    /// Matched by name, which is the catalogue's stable identity — ids are
    /// generated per install, so they can't be used to line up a bundled file
    /// with rows already in the store. Custom exercises are left alone.
    @MainActor
    private static func backfillInstructions(from seeds: [ExerciseSeed], context: ModelContext) {
        let withSteps = seeds.filter { !($0.instructions ?? []).isEmpty }
        guard !withSteps.isEmpty else { return }
        let byName = Dictionary(withSteps.map { ($0.name, $0.instructions ?? []) }, uniquingKeysWith: { first, _ in first })

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })
        guard let existing = try? context.fetch(descriptor) else { return }
        for exercise in existing where exercise.instructions.isEmpty {
            if let steps = byName[exercise.name] {
                exercise.instructions = steps
            }
        }
    }
}
