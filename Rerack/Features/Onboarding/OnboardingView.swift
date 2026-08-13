import SwiftUI
import SwiftData

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

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                basics.tag(1)
                health.tag(2)
                firstWorkout.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut, value: page)

            footer
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
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
                }

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Which units?")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    Picker("Units", selection: $unitPreference) {
                        ForEach(UnitPreference.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Which hand do you log with?")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                    Picker("Dominant hand", selection: $dominantHand) {
                        ForEach(DominantHand.allCases) { hand in
                            Text(hand.displayName).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)

                    // §10.1's live preview: the tick visibly changes sides as
                    // you pick, so the setting explains itself instead of
                    // needing a sentence about thumb reach.
                    SetRowPreview(unit: unitPreference)
                        .environment(\.dominantHand, dominantHand)
                        .padding(.top, DS.Space.xs)
                    Text("The tick sits under your thumb.")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .foregroundStyle(.secondary)
                }
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
            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < 3 ? "Continue" : "Start Training")
                    .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)

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
        .animation(.snappy(duration: 0.25), value: dominantHand)
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
