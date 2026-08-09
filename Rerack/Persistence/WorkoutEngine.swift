import Foundation

/// PRD §7.5/§7.8/§7.9: pure rules for how superset rounds and drop chains
/// affect the rest timer. Deliberately simple for this first cut — it
/// assumes group members are doing roughly the same number of sets, which is
/// true for the common case and the one worth getting right first; real
/// usage will show whether the uneven-set-count edge case needs its own rule.
@MainActor
enum WorkoutEngine {
    static func groupMembers(of workoutExercise: WorkoutExercise, in all: [WorkoutExercise]) -> [WorkoutExercise] {
        guard let group = workoutExercise.supersetGroup else { return [workoutExercise] }
        return all.filter { $0.supersetGroup == group }
    }

    /// Top-level sets only (§7.9): a set plus however many drops chained off
    /// it is one round for superset purposes, not one round per drop —
    /// otherwise a drop chain would make this exercise's count outrun a
    /// partner who did the same number of "real" sets.
    static func completedCount(_ workoutExercise: WorkoutExercise) -> Int {
        (workoutExercise.sets ?? []).filter { $0.isCompleted && $0.parentSetID == nil }.count
    }

    /// Whether the chain rooted at `setLog` still has un-ticked drops under
    /// it. Since M6 §9.3 drop rows are persisted the moment they're created,
    /// so this is answerable from the store — it used to be a `hasPendingDrop`
    /// flag the caller had to compute from view state and pass in on trust,
    /// which no background intent could ever have supplied truthfully.
    static func hasOpenDropChain(after setLog: SetLog, in workoutExercise: WorkoutExercise) -> Bool {
        let rootID = setLog.parentSetID ?? setLog.id
        return (workoutExercise.sets ?? []).contains { $0.parentSetID == rootID && !$0.isCompleted }
    }

    /// Rest starts immediately for a standalone exercise with no open drop
    /// chain. Two independent gates, both must clear:
    /// - **Drop chain (§7.9):** an un-ticked drop still hanging off the chain
    ///   this set belongs to means the chain isn't over, so rest is
    ///   suppressed regardless of anything else.
    /// - **Superset round (§7.8):** suppressed until every other member of
    ///   the group has caught up to (or passed) this exercise's completed
    ///   top-level-set count — i.e. the round is actually over, not just one
    ///   member's turn.
    /// Composes correctly for a drop chain inside a superset member: the
    /// group's round can only be judged "over" once each member's own drop
    /// chains have also closed, because a set with an open chain doesn't
    /// count until it's ticked in the first place.
    static func shouldStartRest(
        after setLog: SetLog,
        in workoutExercise: WorkoutExercise,
        allExercises: [WorkoutExercise]
    ) -> Bool {
        guard !hasOpenDropChain(after: setLog, in: workoutExercise) else { return false }
        let members = groupMembers(of: workoutExercise, in: allExercises)
        guard members.count > 1 else { return true }
        let myCount = completedCount(workoutExercise)
        return !members.contains { $0.id != workoutExercise.id && completedCount($0) < myCount }
    }

    /// PRD §7.5: what the rest-complete notification and in-app banner call
    /// "Next" — the same round-robin order described in §7.8.1, computed
    /// fresh rather than stored so there's one source of truth for it.
    /// `ghostsProvider` is the caller's existing `GhostSetResolver` pipeline,
    /// so "how many sets does this exercise have" and "what's the target
    /// weight/reps" agree with what the set rows themselves show.
    /// M6 §3/§8: the island needs an *address*, not a sentence, so this
    /// carries everything both consumers need — the notification uses the
    /// name and payload, the Live Activity additionally uses the ids to
    /// target its intent and the pre-composed labels to render without
    /// touching SwiftData.
    struct NextSetPointer {
        let workoutExerciseID: UUID
        let exerciseName: String
        /// The `SetLog` this points at when the row already exists (a
        /// materialised drop, or an un-ticked top-level row). Nil means the
        /// row is still a ghost and gets created on tick.
        let setLogID: UUID?
        let setIndex: Int
        let setNumber: Int
        let weightKg: Double
        let reps: Int
        /// M6 §5.3: false when neither history nor a routine target resolved
        /// a payload. The island renders `No target yet` and shows `Open`
        /// instead of a tick — a button whose payload is invisible is a
        /// button that writes something you didn't agree to.
        let isPayloadKnown: Bool
        let supersetLabel: String?
        /// `Set 3 of 4` / `Round 3 of 4` / `Drop 1 of 2` / `Warm-up` / `Set 1`
        let positionLabel: String
        /// `3/4` / `A2` / `D1` / `W` / `#3` — M6 §4.3's one-token rule.
        let compactToken: String
        let isDrop: Bool
    }

    /// M6 delta D1: resolve the pointer **cold**, with no "after" anchor.
    /// Needed on launch, crash recovery, and activity restart, where there's
    /// no just-completed exercise to walk forward from.
    static func nextSet(
        in workout: Workout,
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let all = (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        guard !all.isEmpty else { return nil }

        // M6 §3 step 1: an open drop chain outranks everything, wherever it is.
        if let openDrop = firstOpenDrop(in: all) { return openDrop }

        // Anchor on the most recently completed set, if there is one; a
        // workout with nothing logged starts at the first unit.
        let lastCompleted = all
            .flatMap { exercise in (exercise.sets ?? []).map { (exercise, $0) } }
            .filter { $0.1.isCompleted && $0.1.completedAt != nil }
            .max { $0.1.completedAt! < $1.1.completedAt! }

        if let (exercise, _) = lastCompleted {
            return nextSet(after: exercise, allExercises: all, ghostsProvider: ghostsProvider)
        }
        for candidate in all {
            if let found = pointer(for: candidate, allExercises: all, ghostsProvider: ghostsProvider) { return found }
        }
        return nil
    }

    static func nextSet(
        after workoutExercise: WorkoutExercise,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        // M6 delta D4: a chain still open on *this* exercise wins outright —
        // §7.9 forbids interrupting a drop chain with anything.
        if let openDrop = firstOpenDrop(in: [workoutExercise]) { return openDrop }

        let members = groupMembers(of: workoutExercise, in: allExercises)
        guard members.count > 1 else {
            if let mine = pointer(for: workoutExercise, allExercises: allExercises, ghostsProvider: ghostsProvider) { return mine }
            return nextInSequence(after: workoutExercise.orderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider)
        }

        // Round-robin: walk forward from this exercise's position in the
        // group, wrapping around. A member with no sets left (§15 "superset
        // member runs out of sets") is simply skipped — `pointer(for:)`
        // returns nil for it and the loop moves on to the next member.
        let ordered = members.sorted { $0.orderIndex < $1.orderIndex }
        guard let startIndex = ordered.firstIndex(where: { $0.id == workoutExercise.id }) else { return nil }
        for offset in 1...ordered.count {
            let candidate = ordered[(startIndex + offset) % ordered.count]
            if let found = pointer(for: candidate, allExercises: allExercises, ghostsProvider: ghostsProvider) { return found }
        }
        // Whole group is out of sets — fall through to whatever comes next
        // in the workout after the group's last member.
        let groupMaxOrderIndex = ordered.map(\.orderIndex).max() ?? workoutExercise.orderIndex
        return nextInSequence(after: groupMaxOrderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider)
    }

    /// M6 §3 step 1 / §5.2. The first un-ticked drop row, in chain order.
    /// Reachable only because M6 §9.3 gave drop rows database presence before
    /// they're ticked.
    private static func firstOpenDrop(in exercises: [WorkoutExercise]) -> NextSetPointer? {
        for exercise in exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let sets = exercise.sets ?? []
            let chains = Dictionary(grouping: sets.filter { $0.parentSetID != nil }) { $0.parentSetID! }
            // Chains are visited in their parent's row order so a workout
            // with two open chains resolves the earlier one first.
            let parents = sets.filter { $0.parentSetID == nil }.sorted { $0.orderIndex < $1.orderIndex }
            for parent in parents {
                let chain = (chains[parent.id] ?? []).sorted { $0.orderIndex < $1.orderIndex }
                guard let position = chain.firstIndex(where: { !$0.isCompleted }) else { continue }
                let drop = chain[position]
                return NextSetPointer(
                    workoutExerciseID: exercise.id,
                    exerciseName: exercise.exercise?.name ?? "Exercise",
                    setLogID: drop.id,
                    setIndex: drop.orderIndex,
                    setNumber: position + 1,
                    weightKg: drop.addedWeightKg,
                    reps: drop.reps,
                    // A drop added by hand carries reps 0 until it's typed —
                    // §5.3's `unknown`, since there's nothing honest to write.
                    isPayloadKnown: drop.reps > 0,
                    supersetLabel: nil,
                    positionLabel: "Drop \(position + 1) of \(chain.count)",
                    compactToken: "D\(position + 1)",
                    isDrop: true
                )
            }
        }
        return nil
    }

    /// The next set within a single exercise.
    ///
    /// M6 delta D3: length comes from `plannedSetCount` (falling back to the
    /// ghost count), so `+ Add Set` is visible to the pointer.
    /// M6 delta D2: an exercise with no history *and* no routine target is
    /// landed on rather than skipped, with an unknown payload — otherwise the
    /// island silently drops the exercise in exactly the case where the user
    /// most needs the app opened.
    private static func pointer(
        for workoutExercise: WorkoutExercise,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let ghosts = ghostsProvider(workoutExercise)
        let completed = completedCount(workoutExercise)
        let planned = max(workoutExercise.plannedSetCount ?? ghosts.count, 1)
        guard completed < planned else { return nil }

        let ghost = completed < ghosts.count ? ghosts[completed] : ghosts.last
        let supersetLabel = SupersetGrouping.label(for: workoutExercise, among: allExercises)
        let isInSuperset = groupMembers(of: workoutExercise, in: allExercises).count > 1
        let setNumber = completed + 1
        let totalKnown = workoutExercise.plannedSetCount != nil || !ghosts.isEmpty

        let positionLabel: String
        let compactToken: String
        if isInSuperset {
            // §5.1: inside a group, round and set number are the same figure
            // and "round" is the true one.
            positionLabel = totalKnown ? "Round \(setNumber) of \(planned)" : "Round \(setNumber)"
            compactToken = supersetLabel ?? "\(setNumber)/\(planned)"
        } else if totalKnown {
            positionLabel = "Set \(setNumber) of \(planned)"
            compactToken = "\(setNumber)/\(planned)"
        } else {
            positionLabel = "Set \(setNumber)"
            compactToken = "#\(setNumber)"
        }

        return NextSetPointer(
            workoutExerciseID: workoutExercise.id,
            exerciseName: workoutExercise.exercise?.name ?? "Exercise",
            setLogID: (workoutExercise.sets ?? []).first { $0.parentSetID == nil && $0.orderIndex == completed }?.id,
            setIndex: completed,
            setNumber: setNumber,
            weightKg: ghost?.weightKg ?? 0,
            reps: ghost?.reps ?? 0,
            isPayloadKnown: ghost != nil,
            supersetLabel: supersetLabel,
            positionLabel: positionLabel,
            compactToken: compactToken,
            isDrop: false
        )
    }

    /// M6 §5.1: the "Then" line appears **only when the pointer's next step
    /// changes exercise** — its presence is itself the superset signal, and
    /// during straight sets it's absent because `Set 3 of 4` already says
    /// what's next. The payload rides along only for the immediate next
    /// superset member (the one you'll walk to in seconds); anything on the
    /// far side of a rest omits it, because the island will be showing it as
    /// the main payload by the time you get there.
    static func thenLine(
        after pointer: NextSetPointer,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> String? {
        // Mid drop chain: the next step never changes exercise (§7.9 — a
        // chain is uninterruptible), so the line is absent by the rule.
        guard !pointer.isDrop else { return nil }
        guard let current = allExercises.first(where: { $0.id == pointer.workoutExerciseID }) else { return nil }

        let members = groupMembers(of: current, in: allExercises).sorted { $0.orderIndex < $1.orderIndex }
        if members.count > 1 {
            let round = pointer.setNumber
            guard let myIndex = members.firstIndex(where: { $0.id == current.id }) else { return nil }

            // Next member of this round: first one after me still behind `round`.
            for candidate in members[(myIndex + 1)...] where completedCount(candidate) < round {
                guard let target = Self.pointer(for: candidate, allExercises: allExercises, ghostsProvider: ghostsProvider) else { continue }
                let label = target.supersetLabel.map { "\($0) " } ?? ""
                if target.isPayloadKnown {
                    return "Then  \(label)\(target.exerciseName) · \(formattedPayload(weightKg: target.weightKg, reps: target.reps))"
                }
                return "Then  \(label)\(target.exerciseName)"
            }

            // Last member of the round. Back to the top if rounds remain…
            for candidate in members where completedCount(candidate) == round {
                guard let target = Self.pointer(for: candidate, allExercises: allExercises, ghostsProvider: ghostsProvider) else { continue }
                let label = target.supersetLabel.map { "\($0) " } ?? ""
                return "Then  rest, back to \(label)\(target.exerciseName)"
            }

            // …else the group is exhausted after this tick.
            let groupMaxOrderIndex = members.map(\.orderIndex).max() ?? current.orderIndex
            if let next = nextInSequence(after: groupMaxOrderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider) {
                return "Then  \(next.exerciseName)"
            }
            return nil
        }

        // Standalone: only the last planned set changes exercise next.
        let ghosts = ghostsProvider(current)
        let planned = max(current.plannedSetCount ?? ghosts.count, 1)
        guard pointer.setNumber == planned,
              let next = nextInSequence(after: current.orderIndex, allExercises: allExercises, ghostsProvider: ghostsProvider)
        else { return nil }
        return "Then  \(next.exerciseName)"
    }

    /// `12 kg × 6`, trailing `.0` dropped — one implementation of the payload
    /// wording for the notification line, the Then line, and the island.
    static func formattedPayload(weightKg: Double, reps: Int) -> String {
        let weight = weightKg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weightKg)) : String(weightKg)
        return "\(weight) kg × \(reps)"
    }

    private static func nextInSequence(
        after orderIndex: Int,
        allExercises: [WorkoutExercise],
        ghostsProvider: (WorkoutExercise) -> [GhostSet]
    ) -> NextSetPointer? {
        let upcoming = allExercises
            .filter { $0.orderIndex > orderIndex }
            .sorted { $0.orderIndex < $1.orderIndex }
        for candidate in upcoming {
            if let found = pointer(for: candidate, allExercises: allExercises, ghostsProvider: ghostsProvider) { return found }
        }
        return nil
    }
}
