import SwiftUI
import SwiftData

/// PRD §9.3: folders group routines (e.g. "PPL Split", "Deload Week").
/// Picking "None" clears the routine's folder; "New Folder" creates one
/// inline rather than sending you to a separate management screen.
struct FolderPickerSheet: View {
    @Binding var selectedFolder: RoutineFolder?

    @Query(sort: \RoutineFolder.orderIndex) private var folders: [RoutineFolder]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingNewFolderPrompt = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedFolder = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                        Spacer()
                        if selectedFolder == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(folders) { folder in
                    Button {
                        selectedFolder = folder
                        dismiss()
                    } label: {
                        HStack {
                            Text(folder.name)
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Button {
                    showingNewFolderPrompt = true
                } label: {
                    Label("New Folder", systemImage: "plus")
                }
            }
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Folder", isPresented: $showingNewFolderPrompt) {
                TextField("Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") { createFolder() }
            }
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = RoutineFolder(name: trimmed, orderIndex: folders.count)
        modelContext.insert(folder)
        try? modelContext.save()
        selectedFolder = folder
        newFolderName = ""
        dismiss()
    }
}
