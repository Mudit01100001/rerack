import SwiftUI
import SwiftData

/// PRD §6, §9.1, §9.3. Exercise Library (M1) and Routines (M2) are both
/// real here now. Starting a workout — either empty or from a routine — is
/// still a stub; that's the Active Workout screen, M3.
struct WorkoutTabView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Environment(\.modelContext) private var modelContext

    @State private var newRoutine: Routine?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        // Active workout screen ships in M3 (PRD §7).
                    } label: {
                        Label("Start Empty Workout", systemImage: "play.fill")
                    }
                    .disabled(true)
                } footer: {
                    Text("Starting a workout ships in M3.")
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
}

#Preview {
    WorkoutTabView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
}
