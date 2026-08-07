import SwiftUI

/// PRD §7.8: pick another exercise already in this routine to form a
/// superset with. Lists every other exercise in the routine, showing which
/// group (if any) each already belongs to, so grouping two exercises that
/// are themselves already grouped with others merges the groups sensibly.
struct GroupWithPickerSheet: View {
    let candidates: [RoutineExercise]
    let onPick: (RoutineExercise) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    onPick(candidate)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.exercise?.name ?? "Exercise")
                                .foregroundStyle(.primary)
                            if let group = candidate.supersetGroup {
                                Text("Currently in Superset \(group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Group With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nothing to group with",
                        systemImage: "link",
                        description: Text("Add another exercise to this routine first.")
                    )
                }
            }
        }
    }
}
