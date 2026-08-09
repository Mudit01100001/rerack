import Foundation

/// Maps an exercise or animal to an asset-catalogue name, so artwork can be
/// dropped in later without touching a single call site.
///
/// **Nothing here needs to exist yet.** Every consumer already asks for a
/// name, checks whether the image resolves, and falls back to a glyph when it
/// doesn't — so the app looks deliberate with zero artwork and gets better
/// the moment files land. Adding an image is: name it per the rule below,
/// drop it in `Assets.xcassets`, done.
enum ExerciseArtwork {
    /// `Incline Dumbbell Bench Press` → `exercise-incline-dumbbell-bench-press`
    ///
    /// Derived rather than stored in a lookup table: a table would need a new
    /// entry for every one of the ~190 catalogue exercises (and the ~600 more
    /// that arrive with free-exercise-db at M11), and would silently go stale
    /// whenever an exercise is renamed.
    static func assetName(for exerciseName: String) -> String {
        "exercise-" + slug(exerciseName)
    }

    /// `African elephant` → `animal-african-elephant`, for the §9.5.1 ladder.
    static func animalAssetName(for animalName: String) -> String {
        "animal-" + slug(animalName)
    }

    private static func slug(_ value: String) -> String {
        var slug = ""
        var lastWasHyphen = false
        for character in value.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasHyphen = false
            } else if !lastWasHyphen && !slug.isEmpty {
                slug.append("-")
                lastWasHyphen = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}
