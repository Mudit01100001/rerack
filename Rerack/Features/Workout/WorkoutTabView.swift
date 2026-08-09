import SwiftUI
import SwiftData

/// PRD §6, §7, §9.1, §9.3.
///
/// **Two buttons that looked like duplicates, and why there's now one.**
/// "Start Empty Workout" began a session with no plan; "New Workout" built a
/// reusable plan for later. Genuinely different actions, but once routines
/// were renamed to workouts the labels stopped saying so, and two adjacent
/// buttons reading "…Workout" is a coin flip.
///
/// Resolved by naming the *verb* rather than the noun: **Quick Start** begins
/// logging right now, **Build** creates something you'll run again. The plans
/// themselves are "workouts" (the list below), so the noun keeps one meaning.
struct WorkoutTabView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    @Query private var profiles: [UserProfile]
    @State private var newRoutine: Routine?

    private var activeSplitName: String? {
        profiles.first?.activeSplitName.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quickStartButton
                        .listRowInsets(EdgeInsets(top: DS.Space.xs, leading: DS.Space.md, bottom: DS.Space.xs, trailing: DS.Space.md))
                    splitRow
                    buildRow
                    templatesRow
                } footer: {
                    if coordinator.liveWorkout != nil {
                        Text("Finish or discard your current workout first.")
                    } else if routines.isEmpty {
                        Text("New here? A template drops a whole split into your library in one tap.")
                    }
                }

                RoutineListView()
            }
            .navigationTitle("Workout")
            .sheet(item: $newRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }

    // MARK: - Top actions

    /// Starts logging immediately with nothing planned. Prominent because
    /// it's the one action here that begins a session rather than managing
    /// the library.
    private var quickStartButton: some View {
        Button(action: startEmptyWorkout) {
            Label("Quick Start", systemImage: "play.fill")
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.accentColor, in: .rect(cornerRadius: DS.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(coordinator.liveWorkout != nil)
        .opacity(coordinator.liveWorkout != nil ? 0.5 : 1)
        .listRowSeparator(.hidden)
    }

    private var splitRow: some View {
        NavigationLink {
            SplitSelectorView()
        } label: {
            HStack {
                Label("Current Split", systemImage: "calendar.badge.clock")
                Spacer()
                Text(activeSplitName ?? "Not set")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var buildRow: some View {
        Button {
            createRoutine()
        } label: {
            Label("Build a Workout", systemImage: "square.and.pencil")
                .foregroundStyle(.primary)
        }
    }

    private var templatesRow: some View {
        NavigationLink {
            TemplateLibraryView()
        } label: {
            Label("Start from a Template", systemImage: "square.stack.3d.up")
        }
    }

    /// Inserted immediately so the editor sheet has something to bind to.
    /// `RoutineEditorView.cancel()` deletes it again if it's left unnamed
    /// and empty.
    ///
    /// The exercise library used to sit on this screen as a fifth row. It's
    /// gone: browsing exercises is only useful while you're assembling a
    /// workout, and the editor already opens a picker. A permanent entry
    /// point here was a browse surface pretending to be an action.
    private func createRoutine() {
        let routine = Routine(name: "", orderIndex: routines.count)
        modelContext.insert(routine)
        newRoutine = routine
    }

    private func startEmptyWorkout() {
        guard coordinator.liveWorkout == nil else { return }
        let workout = WorkoutStarter.startEmptyWorkout(context: modelContext)
        coordinator.present(workout)
    }
}

#Preview {
    WorkoutTabView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
        .environment(ActiveWorkoutCoordinator())
}
