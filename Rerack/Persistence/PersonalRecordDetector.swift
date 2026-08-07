import Foundation
import SwiftData

/// PRD §13.4. Runs once per workout, on **finish** — not per-set — because
/// Best Session Volume needs every completed set for an exercise across the
/// whole session, not just the one just ticked. Entirely skipped when
/// `workout.trackedAsProgress == false` (§9.3: a deload/testing session still
/// logs and exports, it just never touches PRs or graphs).
@MainActor
enum PersonalRecordDetector {
    /// One completed set plus the value it's being judged on for a given PR
    /// type — kept together so the winning set can be flagged once the
    /// winning value is known.
    private struct Candidate {
        let value: Double
        let setLog: SetLog
    }

    /// Returns how many new records this session broke, for the summary
    /// screen's "N new records" line (§9.4). Callers that don't need the
    /// count (there are none yet, but this keeps the API honest) can ignore it.
    @discardableResult
    static func detect(workout: Workout, context: ModelContext) -> Int {
        guard workout.trackedAsProgress else { return 0 }

        var newRecordCount = 0
        // Group by underlying Exercise, not by WorkoutExercise: the same
        // exercise can appear more than once in a session (e.g. two
        // superset members performed independently), and Best Session
        // Volume (§13.4) is defined per exercise for the whole session, not
        // per appearance in the exercise list.
        let byExercise = Dictionary(grouping: workout.exercises ?? []) { $0.exercise?.id }
        for workoutExercises in byExercise.values {
            guard let exercise = workoutExercises.first?.exercise else { continue }
            let completedSets = workoutExercises.flatMap { $0.sets ?? [] }.filter(\.isCompleted)
            guard !completedSets.isEmpty else { continue }
            newRecordCount += evaluate(exercise: exercise, completedSets: completedSets, workout: workout, context: context)
        }
        return newRecordCount
    }

    /// The four PR types, each per PRD §13.4's exact predicate. Ties never
    /// count — `breaksRecord` is a strict `>`.
    private static func evaluate(exercise: Exercise, completedSets: [SetLog], workout: Workout, context: ModelContext) -> Int {
        var count = 0

        // Heaviest Weight — max(effective load) over sets with reps ≥ 1,
        // drop sets excluded (§7.9: a drop is by definition lighter than its
        // parent, so it can never legitimately be the heaviest set anyway).
        let heaviestCandidates = completedSets
            .filter { $0.setType != .drop && $0.reps >= 1 }
            .map { Candidate(value: $0.effectiveLoadKg, setLog: $0) }
        count += tryRecord(.heaviestWeight, among: heaviestCandidates, exercise: exercise, workout: workout, context: context)

        // Best 1RM — max Epley estimate. `OneRepMax.estimate` already returns
        // nil for drop sets and for reps > 12 (§13.3), so that's the single
        // source of truth for exclusion here — no extra filtering needed.
        let e1RMCandidates = completedSets.compactMap { set -> Candidate? in
            guard let e1rm = OneRepMax.estimate(weightKg: set.effectiveLoadKg, reps: set.reps, setType: set.setType) else { return nil }
            return Candidate(value: e1rm, setLog: set)
        }
        count += tryRecord(.best1RM, among: e1RMCandidates, exercise: exercise, workout: workout, context: context)

        // Best Set Volume — max single-set volume; drop sets included
        // (§7.9: "each set in the chain evaluated individually").
        let setVolumeCandidates = completedSets.map { Candidate(value: $0.setVolumeKg, setLog: $0) }
        count += tryRecord(.bestSetVolume, among: setVolumeCandidates, exercise: exercise, workout: workout, context: context)

        // Best Session Volume — Σ volume for this exercise this session,
        // drop sets included. There's no single "winning set" for a sum, so
        // the set that contributed the most volume is flagged as the anchor
        // — the closest honest answer to "which set does the trophy belong to."
        let sessionVolume = completedSets.reduce(0) { $0 + $1.setVolumeKg }
        if let anchor = completedSets.max(by: { $0.setVolumeKg < $1.setVolumeKg }),
           breaksRecord(.bestSessionVolume, value: sessionVolume, exercise: exercise, context: context) {
            write(.bestSessionVolume, value: sessionVolume, exercise: exercise, sourceSet: anchor, workout: workout, context: context)
            count += 1
        }

        return count
    }

    private static func tryRecord(_ type: PRType, among candidates: [Candidate], exercise: Exercise, workout: Workout, context: ModelContext) -> Int {
        guard let winner = candidates.max(by: { $0.value < $1.value }) else { return 0 }
        guard breaksRecord(type, value: winner.value, exercise: exercise, context: context) else { return 0 }
        write(type, value: winner.value, exercise: exercise, sourceSet: winner.setLog, workout: workout, context: context)
        return 1
    }

    /// `nil` means this exercise has never had this PR type recorded before
    /// — i.e. this is the first-ever workout containing it. There's nothing
    /// to beat, so the first legitimate value always counts as a new record
    /// rather than requiring a silent "baseline" session that sets nothing.
    private static func currentBest(_ type: PRType, exercise: Exercise, context: ModelContext) -> Double? {
        let exerciseID = exercise.id
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.typeRaw == typeRaw }
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return nil }
        return records.map(\.valueKg).max()
    }

    /// Ties don't count (§13.4) — strictly greater only.
    private static func breaksRecord(_ type: PRType, value: Double, exercise: Exercise, context: ModelContext) -> Bool {
        guard let best = currentBest(type, exercise: exercise, context: context) else { return true }
        return value > best
    }

    private static func write(_ type: PRType, value: Double, exercise: Exercise, sourceSet: SetLog, workout: Workout, context: ModelContext) {
        let record = PersonalRecord(
            type: type,
            valueKg: value,
            exercise: exercise,
            achievedAt: workout.endedAt ?? Date(),
            sourceSetLogID: sourceSet.id,
            sourceWorkoutID: workout.id
        )
        context.insert(record)
        sourceSet.prFlags.insert(flag(for: type))
    }

    private static func flag(for type: PRType) -> PRFlags {
        switch type {
        case .heaviestWeight: return .heaviestWeight
        case .best1RM: return .best1RM
        case .bestSetVolume: return .bestSetVolume
        case .bestSessionVolume: return .bestSessionVolume
        }
    }
}
