import Foundation
import SwiftData

/// PRD §14. Two files: the full per-set workout export (52 columns, one row
/// per logged `SetLog`) and a small measures export. Both are RFC 4180,
/// UTF-8 with a BOM (so Excel on Windows doesn't mis-detect the encoding),
/// ISO-8601 dates, written to a temp file and handed to the caller as a
/// `URL` for the system share sheet — "nothing leaves the device unless you
/// send it," same as the finish-flow photo.
@MainActor
enum CSVExporter {
    private static let bom = "\u{FEFF}"
    private static let crlf = "\r\n"

    // MARK: - Workout export

    /// One row per persisted `SetLog` — completed *and* the rare un-ticked
    /// row a workout can still end with (§7.2 lets you revert a tick without
    /// deleting the row). `is_completed` exists precisely so a CSV consumer
    /// can filter those out; silently excluding them here would make that
    /// column always read `TRUE` and quietly hide real data.
    static func exportWorkouts(context: ModelContext) -> URL? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        guard let workouts = try? context.fetch(descriptor) else { return nil }

        let topTags = topTenTags(across: workouts)
        var rows: [[String]] = [workoutHeader(topTags: topTags)]
        for workout in workouts {
            rows.append(contentsOf: workoutRows(for: workout, topTags: topTags))
        }
        return write(rows, filenamePrefix: "export")
    }

    /// PRD §14 col. 13: "one-hot for the 10 most-used tags, for slicers."
    /// Named after the tags themselves rather than literally `tag_1`…`tag_10`
    /// — a numbered header with no legend can't actually be sliced on in
    /// Excel, which is the one stated purpose of the column.
    private static func topTenTags(across workouts: [Workout]) -> [String] {
        var counts: [String: Int] = [:]
        for workout in workouts {
            for tag in workout.tags { counts[tag, default: 0] += 1 }
        }
        return counts.keys
            .sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
            .prefix(10)
            .map { $0 }
    }

    private static func workoutHeader(topTags: [String]) -> [String] {
        var columns = [
            "workout_id", "workout_title", "routine_id", "routine_name", "split", "date", "day_of_week",
            "week_of_year", "start_time", "end_time", "duration_sec", "location", "tags",
        ]
        columns += topTags.map { "tag_\(sanitizedColumnName($0))" }
        columns += [
            "workout_notes", "has_photo", "exercise_order", "exercise_id", "exercise_name",
            "equipment", "primary_muscle", "secondary_muscles", "load_type", "superset_group",
            "superset_position", "exercise_notes", "set_index", "set_type", "parent_set_index",
            "drop_position", "added_weight_kg", "bodyweight_factor", "effective_load_kg",
            "effective_load_lb", "reps", "rpe", "is_completed", "completed_at", "logged_from",
            "set_volume_kg", "e1rm_kg", "is_pr_weight", "is_pr_1rm", "is_pr_set_volume",
            "rest_after_sec", "exercise_volume_kg", "exercise_sets", "session_volume_kg",
            "session_sets", "session_reps", "bodyweight_kg", "tracked_as_progress", "app_version",
        ]
        return columns
    }

    private static func workoutRows(for workout: Workout, topTags: [String]) -> [[String]] {
        let exercises = (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        // Chronology across the whole workout, for `rest_after_sec` below —
        // every completed set, any exercise, in the order it actually happened.
        let chronological = exercises
            .flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.completedAt != nil }
            .sorted { $0.completedAt! < $1.completedAt! }
        let nextCompletedAt: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: zip(chronological, chronological.dropFirst()).map { ($0.id, $1.completedAt!) }
        )

        var rows: [[String]] = []
        for workoutExercise in exercises {
            rows.append(contentsOf: setRows(for: workoutExercise, in: workout, among: exercises, topTags: topTags, nextCompletedAt: nextCompletedAt))
        }
        return rows
    }

    private static func setRows(
        for workoutExercise: WorkoutExercise,
        in workout: Workout,
        among exercises: [WorkoutExercise],
        topTags: [String],
        nextCompletedAt: [UUID: Date]
    ) -> [[String]] {
        guard let exercise = workoutExercise.exercise else { return [] }

        let topLevel = (workoutExercise.sets ?? [])
            .filter { $0.parentSetID == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
        let dropsByParent = Dictionary(grouping: (workoutExercise.sets ?? []).filter { $0.parentSetID != nil }) { $0.parentSetID! }

        let completed = (workoutExercise.sets ?? []).filter(\.isCompleted)
        let exerciseVolumeKg = completed.reduce(0) { $0 + $1.setVolumeKg }
        let exerciseSets = completed.count

        // §7.9/§13.2: reconstruct the same top-to-bottom logical order the
        // active-workout screen renders (parent, then its drops, then the
        // next parent) rather than raw DB `orderIndex` — a drop's stored
        // `orderIndex` is an unrelated insertion counter (ExerciseCardView's
        // `commitDrop`), not a position, so it can't be sorted against a
        // top-level set's `orderIndex` directly.
        var setIndexByID: [UUID: Int] = [:]
        var nextSetIndex = 1
        var orderedSets: [(setLog: SetLog, parentSetIndex: Int?, dropPosition: Int?)] = []
        for parent in topLevel {
            setIndexByID[parent.id] = nextSetIndex
            orderedSets.append((parent, nil, nil))
            nextSetIndex += 1
            let drops = (dropsByParent[parent.id] ?? []).sorted { $0.orderIndex < $1.orderIndex }
            for (position, drop) in drops.enumerated() {
                setIndexByID[drop.id] = nextSetIndex
                orderedSets.append((drop, setIndexByID[parent.id], position + 1))
                nextSetIndex += 1
            }
        }

        let supersetGroup = workoutExercise.supersetGroup ?? ""
        let supersetPosition = SupersetGrouping.label(for: workoutExercise, among: exercises)
            .flatMap { label -> String? in
                guard let group = workoutExercise.supersetGroup else { return nil }
                return label.hasPrefix(group) ? String(label.dropFirst(group.count)) : nil
            } ?? ""

        return orderedSets.map { entry in
            var row = [
                workout.id.uuidString,
                workout.title,
                workout.routine?.id.uuidString ?? "",
                workout.routineNameSnapshot ?? "",
                workout.splitSnapshot ?? "",
                dateOnly(workout.startedAt),
                dayOfWeek(workout.startedAt),
                isoWeek(workout.startedAt),
                iso8601(workout.startedAt),
                workout.endedAt.map(iso8601) ?? "",
                String(Int(ProfileStats.duration(of: workout))),
                workout.location ?? "",
                workout.tags.joined(separator: "; "),
            ]
            row += topTags.map { workout.tags.contains($0) ? "TRUE" : "FALSE" }
            row += [
                workout.notes ?? "",
                workout.photoFilename != nil ? "TRUE" : "FALSE",
                String(workoutExercise.orderIndex + 1),
                exercise.id.uuidString,
                exercise.name,
                exercise.equipment.displayName,
                exercise.primaryMuscle.displayName,
                exercise.secondaryMuscles.map(\.displayName).joined(separator: "; "),
                exercise.loadType.rawValue,
                supersetGroup,
                supersetPosition,
                workoutExercise.notes ?? "",
                String(setIndexByID[entry.setLog.id] ?? 0),
                entry.setLog.setType.rawValue,
                entry.parentSetIndex.map(String.init) ?? "",
                entry.dropPosition.map(String.init) ?? "",
                formattedNumber(entry.setLog.addedWeightKg),
                formattedNumber(exercise.bodyweightFactor),
                formattedNumber(entry.setLog.effectiveLoadKg),
                formattedNumber(entry.setLog.effectiveLoadKg * 2.2046226218, decimals: 2),
                String(entry.setLog.reps),
                entry.setLog.rpe.map { formattedNumber($0) } ?? "",
                entry.setLog.isCompleted ? "TRUE" : "FALSE",
                entry.setLog.completedAt.map(iso8601) ?? "",
                entry.setLog.loggedFrom.rawValue,
                formattedNumber(entry.setLog.setVolumeKg),
                OneRepMax.estimate(weightKg: entry.setLog.effectiveLoadKg, reps: entry.setLog.reps, setType: entry.setLog.setType).map { formattedNumber($0) } ?? "",
                entry.setLog.prFlags.contains(.heaviestWeight) ? "TRUE" : "FALSE",
                entry.setLog.prFlags.contains(.best1RM) ? "TRUE" : "FALSE",
                entry.setLog.prFlags.contains(.bestSetVolume) ? "TRUE" : "FALSE",
                restAfterSec(entry.setLog, nextCompletedAt: nextCompletedAt),
                formattedNumber(exerciseVolumeKg),
                String(exerciseSets),
                formattedNumber(workout.cachedVolumeKg),
                String(workout.cachedSetCount),
                String(workout.cachedRepCount),
                workout.bodyweightKg.map { formattedNumber($0) } ?? "",
                workout.trackedAsProgress ? "TRUE" : "FALSE",
                appVersion,
            ]
            return row
        }
    }

    /// Derived from consecutive `completedAt` timestamps across the whole
    /// workout, not read from a stored rest-timer log — the app only ever
    /// persists `restStartedAt` per set (PRD §7.5), never how long a rest
    /// actually ran. This is the honest "observed" proxy that data supports:
    /// the wall-clock gap to whatever was ticked next. Blank for the
    /// workout's last completed set, since there's nothing after it.
    private static func restAfterSec(_ setLog: SetLog, nextCompletedAt: [UUID: Date]) -> String {
        guard setLog.isCompleted, let completedAt = setLog.completedAt, let next = nextCompletedAt[setLog.id] else { return "" }
        return String(Int(next.timeIntervalSince(completedAt)))
    }

    // MARK: - Measures export

    static func exportMeasures(context: ModelContext) -> URL? {
        let descriptor = FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date)])
        guard let metrics = try? context.fetch(descriptor) else { return nil }

        var rows: [[String]] = [["date", "metric", "value", "unit", "source"]]
        for metric in metrics {
            rows.append([
                iso8601(metric.date),
                metric.type.rawValue,
                formattedNumber(metric.value),
                metric.type == .bodyweight ? "kg" : "%",
                metric.source.rawValue,
            ])
        }
        return write(rows, filenamePrefix: "measures")
    }

    // MARK: - Formatting helpers

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.timeZone = .current
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func dateOnly(_ date: Date) -> String { dateOnlyFormatter.string(from: date) }
    private static func dayOfWeek(_ date: Date) -> String { dayOfWeekFormatter.string(from: date) }
    private static func iso8601(_ date: Date) -> String { internetDateFormatter.string(from: date) }

    private static func isoWeek(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else { return "" }
        return String(format: "%d-W%02d", year, week)
    }

    private static func formattedNumber(_ value: Double, decimals: Int = 2) -> String {
        // Whole numbers print bare (e.g. `12`) rather than `12.00`, matching
        // the PRD's own examples (`added_weight_kg` `12.0`... close enough —
        // trailing `.0` is the one exception kept, since a bare weight column
        // reading as an integer elsewhere in the file would look truncated.
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.\(decimals)f", value)
    }

    private static func sanitizedColumnName(_ tag: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return tag.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce(into: "") { $0.append($1) }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - RFC 4180 writing

    private static func write(_ rows: [[String]], filenamePrefix: String) -> URL? {
        var csv = bom
        for row in rows {
            csv += row.map(escaped).joined(separator: ",") + crlf
        }
        let dateSuffix = dateOnlyFormatter.string(from: Date())
        let filename = "\(AppIdentity.csvExportPrefix)_\(filenamePrefix)_\(dateSuffix).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
