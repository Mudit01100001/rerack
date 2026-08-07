import SwiftUI

/// PRD §6: "While a workout is live, a persistent banner appears above the
/// tab bar on every tab." Shown by `RootTabView` via `.safeAreaInset` when
/// a workout is live but its full-screen cover isn't currently on top.
struct ActiveWorkoutBanner: View {
    let coordinator: ActiveWorkoutCoordinator

    var body: some View {
        Button {
            coordinator.isPresented = true
        } label: {
            HStack {
                Image(systemName: "dumbbell.fill")
                Text(coordinator.liveWorkout?.title ?? "Workout")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text("Tap to return")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
