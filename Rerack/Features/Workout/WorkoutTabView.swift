import SwiftUI
import SwiftData

/// PRD §6, §7, §9.1, §9.3. Exercise Library (M1), Routines (M2), and now
/// starting a workout (M3) are all real.
struct WorkoutTabView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    @State private var newRoutine: Routine?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: startEmptyWorkout) {
                        Label("Start Empty Workout", systemImage: "play.fill")
                    }
                    .disabled(coordinator.liveWorkout != nil)
                } footer: {
                    if coordinator.liveWorkout != nil {
                        Text("Finish or discard your current workout first.")
                    }
                }

                RoutineListView()

                Section {
                    Button {
                        createRoutine()
                    } label: {
                        Label("New Routine", systemImage: "plus")
                    }
                }

                Section {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise Library", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("Workout")
            .sheet(item: $newRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }

    /// Inserted immediately so the editor sheet has something to bind to —
    /// `RoutineEditorView.cancel()` deletes it again if it's left unnamed
    /// and empty.
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
