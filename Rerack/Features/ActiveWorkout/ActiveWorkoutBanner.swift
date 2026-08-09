import SwiftUI

/// PRD §6: "While a workout is live, a persistent banner appears above the
/// tab bar on every tab." Shown by `RootTabView` via `.safeAreaInset` when a
/// workout is live but its full-screen cover isn't currently on top.
///
/// A floating pill rather than a full-width bar: it reads as the workout
/// *parked* somewhere you can get back to, which is the point. Minimising is
/// now the ordinary way to leave a session, so this is the return path and
/// has to look like one.
struct ActiveWorkoutBanner: View {
    let coordinator: ActiveWorkoutCoordinator

    private var elapsed: String {
        guard let startedAt = coordinator.liveWorkout?.startedAt else { return "" }
        let total = max(0, Int(Date().timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Button {
            coordinator.isPresented = true
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "dumbbell.fill")
                    .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .semibold)

                VStack(alignment: .leading, spacing: 0) {
                    Text(coordinator.liveWorkout?.title ?? "Workout")
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .semibold)
                        .lineLimit(1)
                    Text("In progress")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                        .opacity(0.8)
                }

                Spacer(minLength: DS.Space.xs)

                // Counts up live rather than from a stored string, so a
                // parked workout doesn't look frozen.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsed)
                        .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium, design: .rounded)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up")
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .bold)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs + 2)
            .background(Color.accentColor, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.horizontal, DS.Space.md)
            .padding(.bottom, DS.Space.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout in progress. Tap to return.")
    }
}
