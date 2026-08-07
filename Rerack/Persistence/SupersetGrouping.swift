import Foundation

/// Shared by `RoutineExercise` (pre-planned grouping, M2) and
/// `WorkoutExercise` (live grouping, M3 — both explicit and auto-detected).
/// One implementation of "assign the next free letter" / "dissolve a group
/// that's down to one member" rather than two copies that drift apart.
/// `@MainActor` to match the module's default actor isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`, project.yml) — `RoutineExercise` and
/// `WorkoutExercise` are both implicitly MainActor-isolated `@Model`
/// classes, so a nonisolated protocol can't be satisfied by them under
/// Swift 6 strict concurrency.
///
/// Deliberately does NOT inherit `Identifiable`: a `@Model` type's
/// `Identifiable` conformance is itself MainActor-isolated, which can't
/// satisfy the `SendableMetatype` requirement that inheriting it would
/// impose. Declaring `id` directly gives the same capability without that
/// constraint — callers needing a `List` use `id: \.id` explicitly.
@MainActor
protocol SupersetGroupable: AnyObject {
    var id: UUID { get }
    var supersetGroup: String? { get set }
    var orderIndex: Int { get }
}

@MainActor
enum SupersetGrouping {
    static func nextAvailableLetter<T: SupersetGroupable>(among items: [T]) -> String {
        let used = Set(items.compactMap(\.supersetGroup))
        for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            let letter = String(UnicodeScalar(scalar)!)
            if !used.contains(letter) { return letter }
        }
        return "A"
    }

    static func group<T: SupersetGroupable>(_ a: T, with b: T, among items: [T]) {
        let letter = a.supersetGroup ?? b.supersetGroup ?? nextAvailableLetter(among: items)
        a.supersetGroup = letter
        b.supersetGroup = letter
    }

    static func ungroup<T: SupersetGroupable>(_ item: T, among items: [T]) {
        let group = item.supersetGroup
        item.supersetGroup = nil
        if let group { dissolveIfSingle(group, among: items) }
    }

    /// A superset needs 2+ members by definition — if a removal or ungroup
    /// leaves exactly one exercise carrying a group letter, that letter is
    /// cleared too rather than leaving an orphaned "A1" with no partner.
    static func dissolveIfSingle<T: SupersetGroupable>(_ group: String, among items: [T]) {
        let members = items.filter { $0.supersetGroup == group }
        if members.count == 1 {
            members.first?.supersetGroup = nil
        }
    }

    /// "A1", "A2"... — position computed from `orderIndex` among the
    /// group's current members, not stored.
    static func label<T: SupersetGroupable>(for item: T, among items: [T]) -> String? {
        guard let group = item.supersetGroup else { return nil }
        let members = items.filter { $0.supersetGroup == group }.sorted { $0.orderIndex < $1.orderIndex }
        guard let position = members.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "\(group)\(position + 1)"
    }
}
