import SwiftUI
import SwiftData

/// PRD §21. Fourth tab, parallel to Workout rather than nested inside it.
struct CardioTabView: View {
    @Query(sort: \CardioSession.startedAt, order: .reverse) private var sessions: [CardioSession]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSession = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No cardio logged yet",
                        systemImage: "figure.run",
                        description: Text("Log a session, treadmill, bike, run, whatever you did.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            CardioSessionRow(session: session)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Cardio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log cardio session")
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddCardioSessionView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            if let photoFilename = session.photoFilename {
                PhotoStorage.delete(photoFilename)
            }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}

private struct CardioSessionRow: View {
    let session: CardioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(session.activity.displayName, systemImage: session.activity.systemImage)
                    .font(.headline)
                Spacer()
                Text(session.startedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(durationLabel)
                if let distanceMeters = session.distanceMeters {
                    Text("· \(distanceMeters / 1000, specifier: "%.1f") km")
                }
                if let calories = session.caloriesKcal {
                    Text("· \(Int(calories)) kcal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var durationLabel: String {
        let minutes = session.durationSec / 60
        let seconds = session.durationSec % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    CardioTabView()
        .modelContainer(for: [CardioSession.self], inMemory: true)
}
