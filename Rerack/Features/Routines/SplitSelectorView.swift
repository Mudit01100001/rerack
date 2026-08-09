import SwiftUI
import SwiftData

/// Pick the training split you're currently following.
///
/// The selection is deliberately *not* a filter on what you can run — you can
/// still start any workout in your library on any day. It only labels the
/// sessions you log from here on, which is what makes the CSV's `split`
/// column useful: switching programmes week to week becomes a dimension you
/// can slice volume and adherence by, rather than something you have to
/// remember afterwards.
struct SplitSelectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RoutineFolder.orderIndex) private var folders: [RoutineFolder]
    @Query private var profiles: [UserProfile]

    @State private var customName = ""

    private var profile: UserProfile? { profiles.first }
    private var active: String? { profile?.activeSplitName }

    var body: some View {
        List {
            Section {
                ForEach(folders) { folder in
                    row(name: folder.name, detail: "\(folder.routines?.count ?? 0) workouts")
                }
                if folders.isEmpty {
                    Text("Import a template or put your workouts in a folder, and it'll show up here as a split.")
                        .dsFont(DS.TypeScale.caption, relativeTo: .footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Your splits")
            } footer: {
                Text("Workouts you log are tagged with the split that was active at the time. Changing this never re-labels sessions you've already finished.")
            }

            Section("Something else") {
                HStack {
                    TextField("Name a split", text: $customName)
                        .dsFont(DS.TypeScale.body)
                    Button("Set") { apply(customName.trimmingCharacters(in: .whitespaces)) }
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if active != nil {
                    Button("Clear split", role: .destructive) { apply(nil) }
                }
            }
        }
        .navigationTitle("Current Split")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ensureProfile() }
    }

    private func row(name: String, detail: String) -> some View {
        Button {
            apply(name)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .dsFont(DS.TypeScale.body, weight: .medium)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active == name {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func apply(_ name: String?) {
        ensureProfile()
        profile?.activeSplitName = name
        try? modelContext.save()
        customName = ""
    }

    /// Settings can be the first screen to need a profile row (onboarding
    /// hasn't shipped yet), so it's created lazily here as elsewhere.
    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }
}
