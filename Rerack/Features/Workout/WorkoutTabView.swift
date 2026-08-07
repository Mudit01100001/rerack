import SwiftUI
import SwiftData

/// PRD §6, §9.1. M1 scope is the Exercise Library (fully functional).
/// Starting a workout (M3) and building routines (M2) are stubbed here so
/// the tab's shape matches the PRD's information architecture from day one.
struct WorkoutTabView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]

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

                Section("Routines") {
                    if routines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No routines yet")
                                .font(.subheadline.weight(.medium))
                            Text("Routine building ships in M2.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(routines) { routine in
                            Text(routine.name)
                        }
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
        }
    }
}

#Preview {
    WorkoutTabView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
}
