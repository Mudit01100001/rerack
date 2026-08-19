import SwiftUI
import SwiftData
import UIKit

/// PRD §10.1. Four screens, skippable, re-runnable from Settings. Everything
/// set here is changeable later, and the copy says so — a first-run flow that
/// feels like a commitment is a first-run flow people rush.
///
/// Units are asked for here now that conversion is real. They were left out
/// while every screen hardcoded kilograms, because a picker that changes
/// nothing is worse than no picker.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var page = 0
    @State private var displayName = ""
    @State private var unitPreference: UnitPreference = .kg
    @State private var dominantHand: DominantHand = .right
    @State private var healthDecision: HealthDecision = .undecided

    private enum HealthDecision { case undecided, connected, declined }

    /// Derived rather than written as a literal in two places: the footer
    /// used a hardcoded `3`, so inserting the gestures screen would have left
    /// the last page saying "Continue" and going nowhere.
    private static let lastPage = 4

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                basics.tag(1)
                gestures.tag(2)
                health.tag(3)
                firstWorkout.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // Bigger, higher-contrast dots so the "this pages sideways"
            // affordance actually reads instead of hiding as two faint dots.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut, value: page)

            // Shown once, on the very first page, so it doesn't nag anyone
            // who has already discovered the swipe.
            if page == 0 {
                Text("Swipe →")
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.Space.xxs)
            }

            footer
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        // A keyboard toolbar attaches to the software keyboard itself, not
        // to navigation chrome, so it shows for any focused field below this
        // modifier regardless of whether a NavigationStack sits above it —
        // unlike `.principal`/`.navigationBarTrailing` items, it needs no
        // NavigationStack ancestor. Wrapping this view in one just to host a
        // Done button would draw a nav bar nobody asked for and fight the
        // custom footer below, so the toolbar hangs off the outer VStack.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismissKeyboard)
            }
        }
    }

    /// Resigns whichever field currently owns the keyboard. Routed through
    /// `UIApplication` rather than a `FocusState` binding because the Done
    /// key and the tap-anywhere-to-dismiss gesture both need to work no
    /// matter which field — currently just the name field, but this should
    /// keep working if a later page grows one — is focused.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Screens

    private var welcome: some View {
        page(
            icon: "dumbbell.fill",
            title: "Welcome to \(AppIdentity.displayName)",
            body: "A workout log that stays on your phone. No account, no subscription, no network. Your training data never leaves the device."
        ) {
            EmptyView()
        }
    }

    private var basics: some View {
        page(
            icon: "person.fill",
            title: "The basics",
            body: "All of these are changeable later in Settings."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("What should we call you?")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    TextField("Optional", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        // A name typed after a space (e.g. "John Smith")
                        // should capitalise the second word too, not just
                        // whatever autocapitalization the system default
                        // happened to give the first character.
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(dismissKeyboard)
                }

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Which units?")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    Picker("Units", selection: $unitPreference) {
                        ForEach(UnitPreference.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // Hand picker, preview, and caption used to sit as three
                // loose elements in the same VStack — nothing tied them
                // together visually, so the preview read as a decoration
                // rather than as the direct effect of the picker above it.
                // One card makes the relationship obvious at a glance.
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Which hand do you log with?")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    Picker("Dominant hand", selection: $dominantHand) {
                        ForEach(DominantHand.allCases) { hand in
                            Text(hand.displayName).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dominantHand) { _, _ in
                        Haptics.play(.selection)
                    }

                    // §10.1's live preview: the tick visibly changes sides as
                    // you pick, so the setting explains itself instead of
                    // needing a sentence about thumb reach.
                    SetRowPreview(unit: unitPreference)
                        .environment(\.dominantHand, dominantHand)
                        .padding(.top, DS.Space.xs)
                    Text("Preview — this is how a set row will look.")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.secondary)
                    Text("The tick sits under your thumb.")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.md)
                .dsCard(radius: DS.Radius.large)
            }
        }
    }

    private var health: some View {
        page(
            icon: "heart.fill",
            title: "Apple Health",
            body: "Optional, and everything works without it."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                bullet("arrow.down.circle", "Reads bodyweight and body fat", "Charts them under Measures, and folds bodyweight into volume for bodyweight exercises.")
                bullet("arrow.up.circle", "Writes finished workouts", "They show up in the Fitness app alongside everything else.")

                if healthDecision == .connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task {
                            let granted = await HealthKitManager.requestAuthorization()
                            healthDecision = granted ? .connected : .declined
                        }
                    } label: {
                        Text("Connect Apple Health")
                            .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!HealthKitManager.isAvailable)
                }

                if healthDecision == .declined {
                    // §10.1: "never nags again if declined."
                    Text("No problem. You can connect it any time from Profile.")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A swipe nobody knows about is the same as no swipe.
    ///
    /// Set rows carry three gestures that have no visible affordance —
    /// they're the fastest way to work through a session and completely
    /// undiscoverable, which is the one thing onboarding is genuinely for.
    private var gestures: some View {
        page(
            icon: "hand.draw",
            title: "Rows respond to your thumb",
            body: "Logging a session is mostly these two swipes, plus a hold."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Two frozen swipes rather than a third sentence about them —
                // the whole point of this page is that these gestures are
                // invisible until you've seen them once, and a word like
                // "swipe" doesn't show which way the row moves or what was
                // hiding underneath it.
                GestureIllustration(
                    direction: .left,
                    rowOffset: 132,
                    actions: [
                        GestureActionCircle(icon: "arrow.turn.down.right", label: "Drop", tint: .orange),
                        GestureActionCircle(icon: "trash", label: "Delete", tint: .red)
                    ],
                    caption: "Swipe left — add a drop set, or delete the row."
                )

                GestureIllustration(
                    direction: .right,
                    rowOffset: 72,
                    actions: [
                        GestureActionCircle(icon: "plus", label: "Add Set", tint: .accentColor)
                    ],
                    caption: "Swipe right — add another set with the same numbers."
                )

                // The third gesture has no visual to freeze — a long-press
                // plus a drag doesn't read as a still image — so it stays a
                // single line instead of forcing an illustration on it.
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Image(systemName: "hand.tap")
                        .dsFont(DS.TypeScale.body, relativeTo: .body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    Text("Hold a weight or reps field, then drag up or down to nudge it.")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var firstWorkout: some View {
        page(
            icon: "figure.strengthtraining.traditional",
            title: "Ready when you are",
            body: "Templates come with their days and target weights already filled in, the fastest way to start."
        ) {
            EmptyView()
        }
    }

    // MARK: - Chrome

    private func page<Content: View>(
        icon: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Image(systemName: icon)
                    .dsFont(DS.TypeScale.display, relativeTo: .largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, DS.Space.xl)

                Text(title)
                    .dsFont(DS.TypeScale.title, relativeTo: .title, weight: .bold)

                Text(body)
                    .dsFont(DS.TypeScale.body, relativeTo: .body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content()
                    .padding(.top, DS.Space.xs)

                Spacer(minLength: DS.Space.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.lg)
            // Tapping empty space to close the keyboard is the first thing
            // people try, before they'd ever look for a toolbar button.
            // `contentShape` is needed because the VStack's own hit area
            // otherwise only covers its opaque children, leaving the gaps
            // between them untappable.
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissKeyboard)
        }
    }

    private func bullet(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: icon)
                .dsFont(DS.TypeScale.body, relativeTo: .body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                Text(detail)
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                // Nothing on page 0 to go back to, so the button only
                // appears once there's somewhere for it to send you.
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Text("Back")
                            .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .medium)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 50)
                            .padding(.horizontal, DS.Space.sm)
                    }
                    // Plain and secondary on purpose — Continue is the one
                    // button on this screen that should look pressable from
                    // across the room.
                    .buttonStyle(.plain)
                }

                Button {
                    if page < Self.lastPage {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < Self.lastPage ? "Continue" : "Start Training")
                        .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }

            // Skip stays available on every screen, not just the first.
            // Someone who wants in *now* shouldn't have to back out to find it.
            Button("Skip for now", action: finish)
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 34)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }

    // MARK: - Persistence

    /// Writes whatever was chosen and marks onboarding done. Skipping saves
    /// too: a name typed on screen two shouldn't be lost because you skipped
    /// on screen three.
    private func finish() {
        let target = profile ?? {
            let created = UserProfile()
            modelContext.insert(created)
            return created
        }()
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { target.displayName = trimmed }
        target.dominantHand = dominantHand
        target.unitPreference = unitPreference
        target.hasCompletedOnboarding = true
        try? modelContext.save()
        onFinish()
    }
}

// MARK: - Gesture illustrations

/// A frozen mid-swipe set row, built entirely from primitives rather than
/// from `SetRowView`/`SwipeActionRow` — those are being reworked by another
/// agent in this same build, and a private mock here can't be knocked out of
/// date by that change or race it. Values are fixed dummy numbers; this is a
/// picture, not a working row.
private struct GestureRowMock: View {
    /// Nudges the numbers toward the side that stays visible once the row
    /// is offset and clipped, so the picture still says "60 kg × 8" rather
    /// than showing a lone digit at the edge.
    var contentInset: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text("1")
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                .frame(width: 20, alignment: .leading)
                .foregroundStyle(.secondary)
                .padding(.leading, contentInset)
            Text("60 kg")
                .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .medium, design: .rounded)
            Text("×")
                .dsFont(DS.TypeScale.body, relativeTo: .body)
                .foregroundStyle(.tertiary)
            Text("8")
                .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .medium, design: .rounded)
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .dsFont(DS.TypeScale.heading, relativeTo: .title3)
                .foregroundStyle(.green)
        }
        .padding(DS.Space.sm)
        .frame(height: 52)
        .dsCard(radius: DS.Radius.medium)
        .accessibilityHidden(true)
    }
}

/// One revealed action, iOS 26 Mail–style: a solid-filled 44pt circle
/// carries the symbol, and the label sits *below and outside* it rather than
/// inside — a coloured strip with centred icon-over-label is the look this
/// is deliberately moving away from (see plan item B).
private struct GestureActionCircle: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: DS.Space.xxs) {
            Circle()
                .fill(tint)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .semibold)
                        .foregroundStyle(.white)
                )
            Text(label)
                .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A mock row shifted sideways to reveal the circles it would normally hide,
/// as a still image rather than something the reader has to try for
/// themselves to understand. `rowOffset` must clear the revealed circles'
/// combined width or the row's own card background hides them instead of
/// exposing them.
private struct GestureIllustration: View {
    enum Direction {
        /// Row slides left; actions are revealed on the right.
        case left
        /// Row slides right; actions are revealed on the left.
        case right
    }

    let direction: Direction
    let rowOffset: CGFloat
    let actions: [GestureActionCircle]
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            // The row slides *under the frame's edge*, the way a real row
            // slides under the screen edge in Mail. Without the clip the mock
            // shot off both sides of the page — the left one was cut down to
            // a lone "8" and the right one bled past the margin.
            ZStack(alignment: direction == .left ? .trailing : .leading) {
                HStack(spacing: DS.Space.md) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        action
                    }
                }
                .padding(.horizontal, DS.Space.xs)

                // For the left swipe the row's leading edge slides under the
                // clip, so the numbers move inward by the same amount and
                // stay readable; the right swipe reveals from the left, so
                // its leading content is already safe.
                GestureRowMock(contentInset: direction == .left ? rowOffset : 0)
                    .offset(x: direction == .left ? -rowOffset : rowOffset)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))

            Text(caption)
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// A non-interactive set row, purely so the dominant-hand choice shows its
/// effect. Mirrors `SetRowView`'s column widths rather than embedding it —
/// the real row needs a `SetLog` and a model context, neither of which
/// exists yet during onboarding.
private struct SetRowPreview: View {
    var unit: UnitPreference = .kg
    @Environment(\.dominantHand) private var dominantHand

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if dominantHand == .left { tick }
            Text("1")
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                .frame(width: 26, alignment: .leading)
                .foregroundStyle(.secondary)
            Text("\(Weight.format(kg: 20, in: unit))×5")
                .dsFont(DS.TypeScale.caption, relativeTo: .caption, design: .rounded)
                .foregroundStyle(.tertiary)
                .frame(width: 66, alignment: .leading)
            field(Weight.format(kg: 20, in: unit), width: 58)
            field("5", width: 48)
            Spacer(minLength: 0)
            if dominantHand == .right { tick }
        }
        .padding(DS.Space.sm)
        .dsCard(radius: DS.Radius.medium)
        .animation(.snappy(duration: 0.3), value: dominantHand)
        .accessibilityHidden(true)
    }

    private var tick: some View {
        Image(systemName: "checkmark.circle.fill")
            .dsFont(DS.TypeScale.heading, relativeTo: .title3)
            .foregroundStyle(.green)
            .frame(width: 30)
    }

    private func field(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .medium, design: .rounded)
            .frame(width: width, height: 34)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: .rect(cornerRadius: DS.Radius.small, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}
