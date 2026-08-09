import Foundation
import SwiftData

/// Dev-authored starter routines a user can import in one tap, so a new
/// install isn't an empty routine list and a returning user never re-types a
/// split they already know.
///
/// Templates are **plain data, not a schema** — importing one creates
/// ordinary `Routine` rows and then forgets where they came from. Nothing
/// syncs back, nothing updates when the app ships a new template version, and
/// an imported routine is immediately as editable as one built by hand. That
/// keeps "template" from quietly becoming a second source of truth alongside
/// the routine editor.
struct RoutineTemplate: Identifiable {
    struct SetTarget {
        let weightKg: Double?
        let reps: Int?
    }

    struct ExerciseEntry {
        /// Must match a name in `ExerciseCatalog.json` exactly. Entries that
        /// don't resolve are skipped at import with the rest still landing —
        /// see `TemplateImporter`.
        let exerciseName: String
        let sets: [SetTarget]
        /// §7.8: shared letter groups members into a superset.
        let supersetGroup: String?
        let note: String?

        init(_ exerciseName: String, sets: [SetTarget], supersetGroup: String? = nil, note: String? = nil) {
            self.exerciseName = exerciseName
            self.sets = sets
            self.supersetGroup = supersetGroup
            self.note = note
        }

        /// Convenience for the common "N identical sets" case.
        static func uniform(_ name: String, sets: Int, weightKg: Double?, reps: Int?, supersetGroup: String? = nil, note: String? = nil) -> ExerciseEntry {
            ExerciseEntry(
                name,
                sets: Array(repeating: SetTarget(weightKg: weightKg, reps: reps), count: sets),
                supersetGroup: supersetGroup,
                note: note
            )
        }
    }

    struct RoutineEntry {
        let name: String
        let exercises: [ExerciseEntry]
    }

    let id: String
    let title: String
    /// One line under the title in the browse list.
    let summary: String
    /// Longer prose on the detail screen — what the split is for and what it
    /// deliberately leaves out.
    let detail: String
    let daysPerWeek: String
    /// Surfaces one template as the starting recommendation. Internal name
    /// only — the UI badge says "RECOMMENDED", never anything about who
    /// wrote it.
    let isRecommended: Bool
    let routines: [RoutineEntry]

    var exerciseCount: Int { routines.reduce(0) { $0 + $1.exercises.count } }
}

// MARK: - The bundled set

extension RoutineTemplate {
    static let all: [RoutineTemplate] = [.pushPullLegs, .bodyPartSplit, .arnold, .upperLower, .fullBody]

    /// A five-day upper-focused split, shipped with real working weights
    /// already filled in so the first session has targets rather than empty
    /// rows. Legs are deliberately absent — see the detail copy.
    static let bodyPartSplit = RoutineTemplate(
        id: "body-part-split",
        title: "Body Part Split",
        summary: "Five days, one or two muscle groups each, upper body only",
        detail: """
        One or two muscle groups per day, five days a week, with working \
        weights already filled in so your first session has targets instead \
        of blank rows. Adjust them as you go and the app tracks from there.

        Chest and back are each trained twice a week; arms get a dedicated \
        day on top of the pressing and pulling that already hits them.

        Worth knowing: grouping by body part means overlap. Chest days \
        already work your shoulders and triceps, and back days already work \
        your biceps, so the arm day lands on muscles that aren't fully \
        recovered. Push / Pull / Legs handles that more cleanly. This split \
        wins on being easy to follow and easy to skip a day of.

        No leg day, by design. If you train legs, add a day or start from \
        Push / Pull / Legs instead.
        """,
        daysPerWeek: "5 days",
        isRecommended: true,
        routines: [
            RoutineEntry(name: "Mon: Chest & Shoulders", exercises: [
                // The doc records two loads on this movement — a heavy top
                // set and a lighter back-off — so it's one exercise with
                // different targets, not two exercises.
                ExerciseEntry("Incline Dumbbell Bench Press", sets: [
                    SetTarget(weightKg: 20, reps: 5),
                    SetTarget(weightKg: 18, reps: 9),
                    SetTarget(weightKg: 18, reps: 9),
                ]),
                .uniform("Cable Fly (Mid)", sets: 3, weightKg: 12.5, reps: 10,
                         note: "12.5 kg per arm. Some machines label the stack as the total for both handles, check before matching the number."),
                .uniform("Dumbbell Lateral Raise", sets: 3, weightKg: 7.5, reps: 10),
                .uniform("Cable Rear Delt Fly", sets: 3, weightKg: 7.5, reps: 10),
            ]),
            RoutineEntry(name: "Tue: Back & Biceps", exercises: [
                .uniform("Lat Pulldown (Wide Grip)", sets: 3, weightKg: 30, reps: 8,
                         note: "30 kg on a kg-labelled stack; 90-110 lb on an imperial one."),
                .uniform("Seated Cable Row", sets: 3, weightKg: 30, reps: 8),
                .uniform("Assisted Pull-Up Machine", sets: 3, weightKg: 18, reps: 8,
                         note: "18 kg of assistance, not load."),
                .uniform("Cable Curl", sets: 3, weightKg: 12.5, reps: 9,
                         note: "Bayesian style, cable behind you, arm back."),
                .uniform("Preacher Curl (Dumbbell)", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Reverse Barbell Curl", sets: 3, weightKg: 12.5, reps: 9),
            ]),
            RoutineEntry(name: "Thu: Shoulders & Triceps", exercises: [
                .uniform("Machine Shoulder Press", sets: 3, weightKg: 40, reps: 9),
                .uniform("Dumbbell Shoulder Press", sets: 3, weightKg: 17.5, reps: 9),
                .uniform("Overhead Cable Triceps Extension", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Dumbbell Triceps Kickback", sets: 3, weightKg: 12.5, reps: 9),
            ]),
            RoutineEntry(name: "Fri: Chest & Back", exercises: [
                ExerciseEntry("Incline Dumbbell Bench Press", sets: [
                    SetTarget(weightKg: 20, reps: 5),
                    SetTarget(weightKg: 18, reps: 9),
                    SetTarget(weightKg: 18, reps: 9),
                ]),
                .uniform("Cable Fly (Mid)", sets: 3, weightKg: 12.5, reps: 10),
                .uniform("Lat Pulldown (Wide Grip)", sets: 3, weightKg: 30, reps: 8),
                .uniform("Seated Cable Row", sets: 3, weightKg: 30, reps: 8),
            ]),
            RoutineEntry(name: "Sat: Biceps & Triceps", exercises: [
                .uniform("Cable Curl", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Preacher Curl (Dumbbell)", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Reverse Barbell Curl", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Overhead Cable Triceps Extension", sets: 3, weightKg: 12.5, reps: 9),
                .uniform("Dumbbell Triceps Kickback", sets: 3, weightKg: 12.5, reps: 9),
            ]),
            RoutineEntry(name: "Rotating: Forearms & Abs", exercises: [
                .uniform("Dumbbell Wrist Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Reverse Barbell Curl", sets: 3, weightKg: 12.5, reps: 12),
                .uniform("Cable Crunch", sets: 3, weightKg: nil, reps: 12),
                .uniform("Plank", sets: 3, weightKg: nil, reps: 1, note: "Log reps as seconds held."),
            ]),
        ]
    )

    static let pushPullLegs = RoutineTemplate(
        id: "ppl",
        title: "Push / Pull / Legs",
        summary: "The standard three-way split, run once or twice a week",
        detail: """
        Everything that presses on one day, everything that pulls on the next, \
        legs on the third. Run it once through for three days a week, or twice \
        for six.

        Weights are left blank on purpose — put in whatever you actually lift \
        on the first session and the app carries it forward from there.
        """,
        daysPerWeek: "3 or 6 days",
        isRecommended: false,
        routines: [
            RoutineEntry(name: "Push", exercises: [
                .uniform("Barbell Bench Press", sets: 4, weightKg: nil, reps: 6),
                .uniform("Incline Dumbbell Bench Press", sets: 3, weightKg: nil, reps: 10),
                .uniform("Machine Shoulder Press", sets: 3, weightKg: nil, reps: 10),
                .uniform("Dumbbell Lateral Raise", sets: 3, weightKg: nil, reps: 15),
                .uniform("Cable Triceps Pushdown (Rope)", sets: 3, weightKg: nil, reps: 12),
                .uniform("Overhead Cable Triceps Extension", sets: 3, weightKg: nil, reps: 12),
            ]),
            RoutineEntry(name: "Pull", exercises: [
                .uniform("Pull-Up", sets: 4, weightKg: nil, reps: 8),
                .uniform("Barbell Bent-Over Row", sets: 4, weightKg: nil, reps: 8),
                .uniform("Seated Cable Row", sets: 3, weightKg: nil, reps: 10),
                .uniform("Face Pull", sets: 3, weightKg: nil, reps: 15),
                .uniform("Dumbbell Curl", sets: 3, weightKg: nil, reps: 10),
                .uniform("Hammer Curl", sets: 3, weightKg: nil, reps: 12),
            ]),
            RoutineEntry(name: "Legs", exercises: [
                .uniform("Barbell Back Squat", sets: 4, weightKg: nil, reps: 6),
                .uniform("Romanian Deadlift", sets: 3, weightKg: nil, reps: 8),
                .uniform("Leg Press", sets: 3, weightKg: nil, reps: 12),
                .uniform("Lying Leg Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Leg Extension", sets: 3, weightKg: nil, reps: 15),
                .uniform("Standing Calf Raise Machine", sets: 4, weightKg: nil, reps: 15),
            ]),
        ]
    )

    /// The Golden Six-era Arnold split — chest/back, shoulders/arms, legs,
    /// each run twice a week. High volume and a six-day commitment; included
    /// because people look it up by name, with the honest caveat that its
    /// frequency is the reason most people abandon it.
    static let arnold = RoutineTemplate(
        id: "arnold",
        title: "Arnold Split",
        summary: "Six days, chest/back, shoulders/arms, legs, twice each",
        detail: """
        Chest and back trained together on the same day, then shoulders and \
        arms, then legs — and the whole thing run twice a week.

        This is high volume and a genuine six-day commitment. It works if you \
        can actually train six days; if you're realistically hitting three or \
        four, Upper/Lower or PPL Advanced will get you further than a plan \
        you keep missing two-thirds of.

        Weights are left blank — fill in what you actually lift on the first \
        session and the app carries it forward.
        """,
        daysPerWeek: "6 days",
        isRecommended: false,
        routines: [
            RoutineEntry(name: "Chest & Back", exercises: [
                .uniform("Barbell Bench Press", sets: 4, weightKg: nil, reps: 8, supersetGroup: "A"),
                .uniform("Barbell Bent-Over Row", sets: 4, weightKg: nil, reps: 8, supersetGroup: "A"),
                .uniform("Incline Dumbbell Bench Press", sets: 3, weightKg: nil, reps: 10, supersetGroup: "B"),
                .uniform("Pull-Up", sets: 3, weightKg: nil, reps: 10, supersetGroup: "B"),
                .uniform("Dumbbell Fly", sets: 3, weightKg: nil, reps: 12),
                .uniform("Seated Cable Row", sets: 3, weightKg: nil, reps: 12),
            ]),
            RoutineEntry(name: "Shoulders & Arms", exercises: [
                .uniform("Overhead Barbell Press", sets: 4, weightKg: nil, reps: 8),
                .uniform("Dumbbell Lateral Raise", sets: 4, weightKg: nil, reps: 12),
                .uniform("Reverse Pec Deck (Rear Delt Fly)", sets: 3, weightKg: nil, reps: 15),
                .uniform("Barbell Curl", sets: 4, weightKg: nil, reps: 10, supersetGroup: "A"),
                .uniform("Cable Triceps Pushdown (Straight Bar)", sets: 4, weightKg: nil, reps: 10, supersetGroup: "A"),
                .uniform("Concentration Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Dumbbell Overhead Triceps Extension", sets: 3, weightKg: nil, reps: 12),
            ]),
            RoutineEntry(name: "Legs", exercises: [
                .uniform("Barbell Back Squat", sets: 5, weightKg: nil, reps: 8),
                .uniform("Romanian Deadlift", sets: 4, weightKg: nil, reps: 10),
                .uniform("Leg Extension", sets: 3, weightKg: nil, reps: 15),
                .uniform("Lying Leg Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Standing Calf Raise Machine", sets: 5, weightKg: nil, reps: 15),
            ]),
        ]
    )

    static let upperLower = RoutineTemplate(
        id: "upper-lower",
        title: "Upper / Lower",
        summary: "Four days, alternating upper and lower body",
        detail: """
        Two upper days and two lower days a week. Hits everything twice \
        without the six-day commitment Push/Pull/Legs asks for at full tilt.
        """,
        daysPerWeek: "4 days",
        isRecommended: false,
        routines: [
            RoutineEntry(name: "Upper A, Strength", exercises: [
                .uniform("Barbell Bench Press", sets: 4, weightKg: nil, reps: 5),
                .uniform("Barbell Bent-Over Row", sets: 4, weightKg: nil, reps: 6),
                .uniform("Overhead Barbell Press", sets: 3, weightKg: nil, reps: 8),
                .uniform("Lat Pulldown (Wide Grip)", sets: 3, weightKg: nil, reps: 10),
                .uniform("Barbell Curl", sets: 3, weightKg: nil, reps: 10),
                .uniform("Cable Triceps Pushdown (Straight Bar)", sets: 3, weightKg: nil, reps: 10),
            ]),
            RoutineEntry(name: "Lower A, Strength", exercises: [
                .uniform("Barbell Back Squat", sets: 4, weightKg: nil, reps: 5),
                .uniform("Romanian Deadlift", sets: 3, weightKg: nil, reps: 8),
                .uniform("Leg Press", sets: 3, weightKg: nil, reps: 10),
                .uniform("Seated Leg Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Standing Calf Raise Machine", sets: 4, weightKg: nil, reps: 15),
            ]),
            RoutineEntry(name: "Upper B, Volume", exercises: [
                .uniform("Incline Dumbbell Bench Press", sets: 4, weightKg: nil, reps: 10),
                .uniform("Seated Cable Row", sets: 4, weightKg: nil, reps: 10),
                .uniform("Dumbbell Shoulder Press", sets: 3, weightKg: nil, reps: 10),
                .uniform("Cable Fly (Mid)", sets: 3, weightKg: nil, reps: 12),
                .uniform("Dumbbell Lateral Raise", sets: 4, weightKg: nil, reps: 15),
                .uniform("Hammer Curl", sets: 3, weightKg: nil, reps: 12),
            ]),
            RoutineEntry(name: "Lower B, Volume", exercises: [
                .uniform("Bulgarian Split Squat", sets: 3, weightKg: nil, reps: 10),
                .uniform("Hack Squat Machine", sets: 3, weightKg: nil, reps: 12),
                .uniform("Lying Leg Curl", sets: 4, weightKg: nil, reps: 12),
                .uniform("Leg Extension", sets: 3, weightKg: nil, reps: 15),
                .uniform("Seated Calf Raise Machine", sets: 4, weightKg: nil, reps: 20),
            ]),
        ]
    )

    static let fullBody = RoutineTemplate(
        id: "full-body",
        title: "Full Body ×3",
        summary: "Three sessions a week, everything each time",
        detail: """
        The most forgiving split there is: miss a day and you've still trained \
        everything that week. Good if your attendance is the variable rather \
        than your effort.
        """,
        daysPerWeek: "3 days",
        isRecommended: false,
        routines: [
            RoutineEntry(name: "Full Body A", exercises: [
                .uniform("Barbell Back Squat", sets: 3, weightKg: nil, reps: 8),
                .uniform("Barbell Bench Press", sets: 3, weightKg: nil, reps: 8),
                .uniform("Barbell Bent-Over Row", sets: 3, weightKg: nil, reps: 8),
                .uniform("Dumbbell Lateral Raise", sets: 3, weightKg: nil, reps: 15),
                .uniform("Plank", sets: 3, weightKg: nil, reps: 1, note: "Log reps as seconds held."),
            ]),
            RoutineEntry(name: "Full Body B", exercises: [
                .uniform("Romanian Deadlift", sets: 3, weightKg: nil, reps: 8),
                .uniform("Overhead Barbell Press", sets: 3, weightKg: nil, reps: 8),
                .uniform("Lat Pulldown (Wide Grip)", sets: 3, weightKg: nil, reps: 10),
                .uniform("Leg Press", sets: 3, weightKg: nil, reps: 12),
                .uniform("Cable Crunch", sets: 3, weightKg: nil, reps: 15),
            ]),
            RoutineEntry(name: "Full Body C", exercises: [
                .uniform("Trap Bar Deadlift", sets: 3, weightKg: nil, reps: 6),
                .uniform("Incline Dumbbell Bench Press", sets: 3, weightKg: nil, reps: 10),
                .uniform("Seated Cable Row", sets: 3, weightKg: nil, reps: 10),
                .uniform("Dumbbell Curl", sets: 3, weightKg: nil, reps: 12),
                .uniform("Cable Triceps Pushdown (Rope)", sets: 3, weightKg: nil, reps: 12),
            ]),
        ]
    )
}

// MARK: - Import

@MainActor
enum TemplateImporter {
    struct Result {
        let routinesCreated: Int
        /// Names that didn't resolve against the catalogue. Surfaced rather
        /// than swallowed — a silently short routine is worse than a note
        /// saying which movement is missing.
        let unmatchedExercises: [String]
    }

    /// Creates a folder holding one `Routine` per day. Import is additive and
    /// repeatable: running it twice gives two folders rather than merging or
    /// overwriting, which keeps it from ever destroying edits made to a
    /// previous import.
    @discardableResult
    static func `import`(_ template: RoutineTemplate, context: ModelContext) -> Result {
        let catalogue = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var byName: [String: Exercise] = [:]
        for exercise in catalogue where !exercise.isArchived {
            byName[exercise.name.lowercased()] = exercise
        }

        let existingFolders = (try? context.fetch(FetchDescriptor<RoutineFolder>()))?.count ?? 0
        let folder = RoutineFolder(name: template.title, orderIndex: existingFolders)
        context.insert(folder)

        var unmatched: [String] = []
        var routinesCreated = 0

        for (routineIndex, routineEntry) in template.routines.enumerated() {
            let routine = Routine(name: routineEntry.name, folder: folder, orderIndex: routineIndex)
            context.insert(routine)
            routinesCreated += 1

            var orderIndex = 0
            for entry in routineEntry.exercises {
                guard let exercise = byName[entry.exerciseName.lowercased()] else {
                    unmatched.append(entry.exerciseName)
                    continue
                }
                let routineExercise = RoutineExercise(
                    orderIndex: orderIndex,
                    exercise: exercise,
                    supersetGroup: entry.supersetGroup
                )
                routineExercise.notes = entry.note
                context.insert(routineExercise)
                routineExercise.routine = routine
                orderIndex += 1

                for (setIndex, target) in entry.sets.enumerated() {
                    let setTemplate = RoutineSetTemplate(
                        orderIndex: setIndex,
                        targetWeightKg: target.weightKg,
                        targetReps: target.reps
                    )
                    context.insert(setTemplate)
                    setTemplate.routineExercise = routineExercise
                }
            }
        }

        try? context.save()
        return Result(routinesCreated: routinesCreated, unmatchedExercises: unmatched)
    }
}
