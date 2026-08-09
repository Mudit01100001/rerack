import Foundation

/// PRD §10.3 and §4 Principle 6 ("no unexplained jargon"): every number in
/// the app that a reasonable person would have to look up gets a `?`.
///
/// Content is bundled, versioned with the app, and never fetched. The voice
/// is set by §10.3's worked example: plain-English answer first, then the
/// detail, then the formula if there is one, then the honest caveats. Never
/// motivational, never coaching (§4 Principle 8 — a logbook, not a coach).
///
/// This is deliberately the same infrastructure that would later serve text
/// form cues in the How To tab (§9.2, §23.3) — build the sheet and registry
/// once, fill it with more content later for free.
enum ExplainerTerm: String, CaseIterable, Identifiable {
    case estimatedOneRepMax
    case volume
    case setVsSessionVolume
    case effectiveLoad
    case rpe
    case personalRecordTypes
    case superset
    case dropSet
    case warmupSets
    case trackAsProgress
    case updateRoutineValues
    case streak
    case ghostSets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedOneRepMax: "Estimated 1RM"
        case .volume: "Volume"
        case .setVsSessionVolume: "Set volume vs. session volume"
        case .effectiveLoad: "Effective load"
        case .rpe: "RPE"
        case .personalRecordTypes: "The four record types"
        case .superset: "Superset"
        case .dropSet: "Drop set"
        case .warmupSets: "Warm-up sets"
        case .trackAsProgress: "Track as progress"
        case .updateRoutineValues: "Update target values"
        case .streak: "Streak"
        case .ghostSets: "Ghost sets"
        }
    }

    /// One-line answer shown in bold at the top of the sheet.
    var summary: String {
        switch self {
        case .estimatedOneRepMax:
            "The heaviest weight you could probably lift once, estimated from a heavier-rep set, so you don't have to actually test it."
        case .volume:
            "Weight times reps, added up. The simplest single number for how much work you did."
        case .setVsSessionVolume:
            "Set volume is one set. Session volume is every set of that exercise in one workout."
        case .effectiveLoad:
            "The weight your muscles actually moved, which for a pull-up is mostly you, not what's on the belt."
        case .rpe:
            "A 1–10 rating of how hard a set felt. You decide it; the app never guesses it for you."
        case .personalRecordTypes:
            "Four different ways to be at your best, because \"strongest\" means more than one thing."
        case .superset:
            "Two exercises done back to back with no rest in between, resting only after the pair."
        case .dropSet:
            "Immediately doing another set at a lighter weight, with no rest, after finishing a normal set."
        case .warmupSets:
            "Sets done to prepare, not to progress, so they're kept out of your volume by default."
        case .trackAsProgress:
            "Whether this workout's sessions count toward your graphs and records."
        case .updateRoutineValues:
            "Whether finishing a session rewrites this workout's targets to match what you actually did."
        case .streak:
            "Consecutive weeks, not days, in which you trained at least once."
        case .ghostSets:
            "The grey numbers already filled in for you: what you did last time."
        }
    }

    /// Markdown body. Paragraphs are split on blank lines by the sheet.
    var body: String {
        switch self {
        case .estimatedOneRepMax:
            """
            If you lift 100 kg for 5 reps, you could probably manage around 117 kg for a single. This app uses the **Epley formula**:

            `1RM = weight × (1 + reps ÷ 30)`

            **Worth knowing:** this is an estimate, not a measurement. There are several formulas — Epley, Brzycki, Lombardi — and they disagree with each other by a few percent. None of them is "correct."

            That's fine, because you're only ever comparing your own numbers to your own. As long as the app uses one formula consistently, the trend is meaningful even if the absolute number is a little off.

            It also gets unreliable above about 12 reps, so the app doesn't calculate it there and leaves it blank rather than showing you a number it doesn't believe. Drop sets are excluded for the same reason — a set done under fatigue produces a meaningless estimate.
            """

        case .volume:
            """
            `volume = weight × reps`

            Do 40 kg for 10 reps and that set is 400 kg of volume. Add up every set and you have your session volume.

            It's a blunt instrument — it treats 100 kg × 1 and 10 kg × 10 as identical, which they obviously aren't. But it's the most useful single number for answering "am I doing more work than last month?", and it's what most progression tracking is built on.

            Warm-up sets are left out by default. You can change that in Settings.
            """

        case .setVsSessionVolume:
            """
            **Set volume** is one set: `weight × reps`.

            **Session volume** is every set of that exercise added together in a single workout.

            They move independently, which is why both are tracked. Adding a fourth set raises session volume without touching set volume. Going heavier on your top set raises set volume without necessarily changing the session total by much.

            If you're chasing intensity, watch set volume. If you're chasing work capacity, watch session volume.
            """

        case .effectiveLoad:
            """
            For a barbell or a machine, effective load is simply what's on the bar or the stack.

            For bodyweight movements it's your bodyweight — or a fraction of it, since a push-up doesn't lift all of you:

            `effective load = (bodyweight × factor) + added weight`

            A pull-up uses a factor of 1.0, a push-up about 0.64, an inverted row about 0.5. A weighted pull-up adds the belt weight on top. An assisted machine subtracts the assistance.

            **Worth knowing:** those factors are reasonable published estimates, not measurements of your body. They're consistent, which is what makes the trend trustworthy — but don't read them as biomechanical fact.

            Your bodyweight comes from Apple Health. Importantly, it's recorded onto each set at the moment you log it and never recalculated — otherwise gaining or losing 5 kg would silently rewrite every pull-up you've ever done.
            """

        case .rpe:
            """
            RPE stands for **Rate of Perceived Exertion**. You give a set a 1–10 rating right after finishing it, based on how many reps you had left:

            - **10** — absolute failure, couldn't have done one more
            - **9** — one more rep was possible
            - **8** — two more reps were possible
            - **7** — three more; comfortable
            - **6 or below** — warm-up territory

            **Why bother:** weight on the bar doesn't tell you how hard a set was. 100 kg × 5 on a good day and 100 kg × 5 on three hours' sleep log identically, but they aren't the same set. RPE is the only field that captures that difference, which makes it useful for spotting fatigue building up weeks before your performance actually drops.

            **Why you might not:** it's a judgement call after every single set, and it's noisy until you've calibrated it over a few months. Plenty of people train well for decades without it. It's off by default for that reason.

            **The app will never fill this in for you.** RPE exists precisely to record something no other number contains — how it felt, to you, that day. If it could be calculated from your weights and reps, it would be redundant. Even sleep or recovery data wouldn't do it: those correlate with expected effort at best, and treating a wearable's guess as your own report would make the number less trustworthy, not more.
            """

        case .personalRecordTypes:
            """
            **Heaviest Weight** — the most you've ever lifted for at least one rep. Pure strength.

            **Best 1RM** — the highest estimated one-rep max, which can improve even when the weight doesn't, if you got more reps out of it.

            **Best Set Volume** — the most `weight × reps` in a single set. Rewards a hard, high-rep set.

            **Best Session Volume** — the most total work for that exercise in one workout. Rewards doing more sets.

            Four records because "getting stronger" isn't one thing. A day where you hit fewer reps at a heavier weight and a day where you grind out more total work are both progress, and only tracking one of them would hide half of it.

            Heaviest Weight and Best 1RM ignore drop sets — those are lighter and fatigued by definition. The volume records count them.

            Ties don't count. You have to actually beat it.
            """

        case .superset:
            """
            You do exercise A, then exercise B immediately, and only then rest. Repeat. It's the standard way to get more work done in less time.

            **What telling the app actually buys you** — this matters, because otherwise it's just a label:

            1. **The rest timer stops interrupting you.** No countdown between A and B; it only starts once the round is genuinely over.
            2. **Your Lock Screen knows what's next.** It can say "next: B, then back to A" instead of assuming you finish one exercise before starting the other.

            You can set one up in advance when building a routine, group two exercises mid-workout, or just start alternating — the app will notice and offer to group them for you. If you say no, it won't ask again.
            """

        case .dropSet:
            """
            You finish a set, immediately strip the weight down, and keep going with no rest. Often repeated more than once.

            The app pre-fills each drop at about 20% lighter than the set above it, rounded to the nearest 2.5 kg. That's a common starting point, not a rule — change it to whatever you actually used.

            **Rest is suppressed for the whole chain.** The timer doesn't start between a set and its drops, or between consecutive drops. It starts once you tick the last one.

            Drops count fully toward your volume records. They're excluded from Heaviest Weight and Best 1RM, since a lighter set done under fatigue isn't evidence of a new maximum.
            """

        case .warmupSets:
            """
            A warm-up set is done to prepare for the working sets, not to drive progress. Marking one keeps it out of your volume totals by default, so a thorough warm-up doesn't inflate the number you're trying to read a trend from.

            It's still logged, still exported, and still visible in your history — it just doesn't count toward the total.

            If you'd rather count everything, there's a setting for it.
            """

        case .trackAsProgress:
            """
            **On** (the default): this routine's sessions feed your graphs and can set personal records.

            **Off**: sessions are still logged, still appear in your history, and still export — they just don't move your progress graphs or trigger records.

            Turn it off for deload weeks, technique days, or a session where you're deliberately going light. Without it, a planned easy week looks like a plateau on the graph.

            Whichever way it's set when you *finish* a workout is what sticks to that workout permanently. Changing the routine setting later doesn't rewrite your history.
            """

        case .updateRoutineValues:
            """
            **On** (the default): when you finish, the routine's target weights and reps are rewritten to match what you actually did.

            **Off**: the targets stay exactly as you first entered them.

            With it on, the routine gradually self-corrects toward reality — you set it up once and never edit it again unless you're deliberately changing the plan. With it off, the routine stays a fixed prescription you're measuring yourself against.

            Either way, the grey suggested numbers on your set rows come from your actual history, not from these targets, once you've done the exercise at least once.
            """

        case .streak:
            """
            A streak here counts **consecutive weeks** (Monday to Sunday) in which you trained at least once. Not consecutive days.

            That's deliberate. A daily streak on a strength app punishes rest days — and rest days are when you actually adapt to the training. A counter that goes red because you took a sensible Wednesday off is measuring the wrong thing and quietly pushing you toward doing the wrong thing.

            Weekly is a fair measure of consistency that survives a normal training split, a busy week, or a deliberate deload.
            """

        case .ghostSets:
            """
            When you start an exercise, the weight and reps boxes are already filled in, in grey. That's what you did last time.

            **Grey means suggestion. Solid means fact.** Nothing grey has been saved yet.

            You have three options: tap the tick to accept it exactly as shown, type over it if today was different, or swipe the row away if you're not doing that set.

            The numbers come from the most recent workout where you actually did that exercise — whichever routine it was in. If you've never done it, they come from your routine's targets instead. If there's nothing to go on, the row is just empty.

            This is the whole point of the app: you shouldn't have to remember what you lifted last Tuesday.
            """
        }
    }
}
