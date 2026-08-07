import SwiftUI

/// Generic over anything `SupersetGroupable` — the routine editor (M2) and
/// the active workout (M3) both need "pick another exercise to superset
/// with," and the only difference between them is the underlying model
/// type, so one sheet serves both rather than two near-identical copies.
struct GroupWithPickerSheet<T: SupersetGroupable>: View {
    let candidates: [T]
    let nameProvider: (T) -> String
    let onPick: (T) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates, id: \.id) { candidate in
                Button {
                    onPick(candidate)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nameProvider(candidate))
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
                        description: Text("Add another exercise first.")
                    )
                }
            }
        }
    }
}
