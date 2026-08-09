import SwiftUI
import SwiftData

/// PRD §6, §7, §9.1, §9.3.
///
/// Layout follows what you actually came here to do. Starting something is at
/// the top; the split you're on is the header over its own days; managing the
/// library sits at the bottom, because you do it rarely.
///
/// The standalone "Current Split" row is gone. It was a setting that looked
/// like a destination and explained nothing about itself. Choosing a split is
/// now the same act as looking at one: the title above the day cards is the
/// picker.
struct WorkoutTabView: View {
    @Query(sort: \Routine.orderIndex) private var routines: [Routine]
    @Query(sort: \RoutineFolder.orderIndex) private var folders: [RoutineFolder]
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    @Query private var profiles: [UserProfile]
    @State private var newRoutine: Routine?
    @State private var showingTemplates = false
    @State private var showingNewSplit = false

    private var profile: UserProfile? { profiles.first }

    /// The split being shown. Falls back to the first folder so the screen is
    /// never empty just because nothing was explicitly chosen.
    private var selectedSplit: String? {
        if let stored = profile?.activeSplitName, folders.contains(where: { $0.name == stored }) {
            return stored
        }
        return folders.first?.name
    }

    private var loose: [Routine] {
        routines.filter { $0.folder == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    startRow
                        .listRowInsets(EdgeInsets(
                            top: cardInset, leading: cardInset, bottom: cardInset, trailing: cardInset
                        ))
                        .listRowSeparator(.hidden)
                }

                if !folders.isEmpty, let selectedSplit {
                    Section {
                        RoutineListView(folderName: selectedSplit)
                    } header: {
                        splitHeader(selectedSplit)
                    }
                }

                if !loose.isEmpty {
                    Section("Not in a split") {
                        RoutineListView(folderName: nil)
                    }
                }

                if routines.isEmpty {
                    Section {
                        emptyState
                    }
                }

                Section {
                    Button {
                        showingTemplates = true
                    } label: {
                        Label("Browse Templates", systemImage: "square.stack.3d.up")
                    }
                    Button {
                        showingNewSplit = true
                    } label: {
                        Label("New Split", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Library")
                }
            }
            .navigationTitle("Workout")
            .sheet(item: $newRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
            .sheet(isPresented: $showingTemplates) {
                NavigationStack { TemplateLibraryView() }
            }
            .sheet(isPresented: $showingNewSplit) {
                NewSplitSheet()
            }
        }
    }

    // MARK: - Top

    /// One row, two intents: build something reusable, or just start logging.
    /// Quick Start is the filled one because it's the only action here that
    /// begins a session.
    /// Padding between the system section's edge and the buttons inside it.
    private let cardInset: CGFloat = DS.Space.xs

    /// The outer container is the ordinary grouped-list section, same as every
    /// other card on this screen — only the buttons' radius is ours to set.
    /// Inner = outer − padding, where outer is the system section radius
    /// (`DS.Radius.medium`), so the curves stay parallel without redrawing the
    /// card itself.
    private var startRow: some View {
        // Outer R = Inner R + Padding, so Inner = Outer − Padding.
        //
        // Outer is the grouped-list section's own radius, which isn't exposed
        // as an API — measured off a render at 26pt (iOS 26 rounds sections
        // far harder than the ~10pt of earlier versions, so the old assumption
        // was badly wrong). Padding is `cardInset` below.
        //
        //     26 − 8 = 18
        let outerRadius: CGFloat = 26
        let innerRadius = outerRadius - cardInset

        return HStack(spacing: cardInset) {
            Button {
                createRoutine()
            } label: {
                Label("New Workout", systemImage: "square.and.pencil")
                    .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .semibold)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: innerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: startEmptyWorkout) {
                Label("Quick Start", systemImage: "play.fill")
                    .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.accentColor, in: .rect(cornerRadius: innerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(coordinator.liveWorkout != nil)
            .opacity(coordinator.liveWorkout != nil ? 0.45 : 1)
        }
    }

    /// The split title *is* the switcher, with Edit beside it.
    ///
    /// The menu label deliberately holds no `Spacer`. A full-width label made
    /// SwiftUI anchor the popover to the centre of that frame, so the menu
    /// appeared in the middle of the screen instead of under the words you
    /// tapped. The `Spacer` lives outside the `Menu` now.
    private func splitHeader(_ current: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Menu {
                Picker("Split", selection: splitBinding) {
                    ForEach(folders) { folder in
                        Text(folder.name).tag(folder.name)
                    }
                }
                Divider()
                Button {
                    showingNewSplit = true
                } label: {
                    Label("New Split", systemImage: "folder.badge.plus")
                }
                Button {
                    showingTemplates = true
                } label: {
                    Label("Start from a Template", systemImage: "square.stack.3d.up")
                }
            } label: {
                HStack(spacing: DS.Space.xxs) {
                    Text(current)
                        .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Reordering is behind Edit rather than always live: a long-press
            // drag that's permanently armed fires by accident on a list whose
            // rows are mostly buttons.
            EditButton()
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
        }
        .textCase(nil)
        .padding(.vertical, DS.Space.xxs)
    }

    /// Writing through the picker keeps "which split am I looking at" and
    /// "which split gets stamped on my workouts" as one fact. They were two
    /// before, which is what made the old row feel arbitrary.
    private var splitBinding: Binding<String> {
        Binding(
            get: { selectedSplit ?? "" },
            set: { newValue in
                ensureProfile()
                profile?.activeSplitName = newValue
                try? modelContext.save()
            }
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("No workouts yet")
                .dsFont(DS.TypeScale.body, relativeTo: .subheadline, weight: .medium)
            Text("Browse templates for a ready-made split, or build your own.")
                .dsFont(DS.TypeScale.caption, relativeTo: .caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Space.xxs)
    }

    // MARK: - Actions

    /// Inserted immediately so the editor sheet has something to bind to.
    /// `RoutineEditorView.cancel()` deletes it again if it's left unnamed and
    /// empty. Lands in the split currently being viewed, since that's almost
    /// always where you meant to put it.
    private func createRoutine() {
        let routine = Routine(name: "", orderIndex: routines.count)
        routine.folder = folders.first { $0.name == selectedSplit }
        modelContext.insert(routine)
        newRoutine = routine
    }

    private func startEmptyWorkout() {
        guard coordinator.liveWorkout == nil else { return }
        let workout = WorkoutStarter.startEmptyWorkout(context: modelContext)
        coordinator.present(workout)
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }
}

/// Creating an empty split, with the template library one tap away — a new
/// split you then have to fill by hand is most of the work still ahead of you.
private struct NewSplitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RoutineFolder.orderIndex) private var folders: [RoutineFolder]
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Split name", text: $name)
                } footer: {
                    Text("A split is a group of workouts you run on a cycle, like Push / Pull / Legs.")
                }

                Section {
                    NavigationLink {
                        TemplateLibraryView(isPushed: true)
                    } label: {
                        Label("Start from a Template", systemImage: "square.stack.3d.up")
                    }
                } footer: {
                    Text("Templates come with their days and target weights already filled in.")
                }
            }
            .navigationTitle("New Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(RoutineFolder(name: trimmed, orderIndex: folders.count))
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    WorkoutTabView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
        .environment(ActiveWorkoutCoordinator())
}
