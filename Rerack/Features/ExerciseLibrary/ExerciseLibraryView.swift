import SwiftUI
import SwiftData

/// PRD §9.1 — M1's one fully-built feature: "search, filter chips by muscle
/// group and equipment, alphabetical sections. Recently used exercises
/// pinned to the top."
struct ExerciseLibraryView: View {
    @Query(
        filter: #Predicate<Exercise> { !$0.isArchived },
        sort: \Exercise.name
    )
    private var exercises: [Exercise]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, this view acts as a picker (used by the routine editor,
    /// M2) instead of the M1 browse experience: tapping a row calls this
    /// and dismisses, rather than opening the quick-detail sheet.
    var onPick: ((Exercise) -> Void)?

    private var isPickMode: Bool { onPick != nil }

    @State private var searchText = ""
    @State private var selectedMuscles: Set<Muscle> = []
    @State private var selectedEquipment: Set<Equipment> = []
    @State private var showingAddCustom = false
    @State private var selectedExercise: Exercise?

    /// Recency tracking is a lightweight, self-contained M1 stand-in — real
    /// "recently used" (from actual workout history) exists once M3 ships.
    @AppStorage("com.mudit.logbook.recentExerciseIDs") private var recentIDsRaw = ""

    private var recentIDs: [UUID] {
        recentIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    private var isFiltering: Bool {
        !searchText.isEmpty || !selectedMuscles.isEmpty || !selectedEquipment.isEmpty
    }

    private var filtered: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscles.isEmpty
                || selectedMuscles.contains(exercise.primaryMuscle)
                || !selectedMuscles.isDisjoint(with: Set(exercise.secondaryMuscles))
            let matchesEquipment = selectedEquipment.isEmpty
                || selectedEquipment.contains(exercise.equipment)
            return matchesSearch && matchesMuscle && matchesEquipment
        }
    }

    private var recentExercises: [Exercise] {
        guard !isFiltering else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return recentIDs.compactMap { byID[$0] }
    }

    private var groupedByLetter: [(letter: String, exercises: [Exercise])] {
        let grouped = Dictionary(grouping: filtered) { exercise -> String in
            String(exercise.name.prefix(1)).uppercased()
        }
        return grouped.keys.sorted().map { letter in
            (letter, grouped[letter]!.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        List {
            if !recentExercises.isEmpty {
                Section("Recent") {
                    ForEach(recentExercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }

            filterSection

            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(groupedByLetter, id: \.letter) { group in
                    Section(group.letter) {
                        ForEach(group.exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Exercise Library")
        .toolbar {
            if isPickMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCustom = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add custom exercise")
            }
        }
        .sheet(isPresented: $showingAddCustom) {
            AddCustomExerciseView()
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
    }

    private var filterSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Muscle.allCases) { muscle in
                            FilterChip(
                                title: muscle.displayName,
                                isSelected: selectedMuscles.contains(muscle)
                            ) {
                                toggle(muscle, in: &selectedMuscles)
                            }
                        }
                    }
                    .padding(.horizontal, 1) // keeps the first chip's shadow/edge from clipping
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Equipment.allCases) { equipment in
                            FilterChip(
                                title: equipment.displayName,
                                isSelected: selectedEquipment.contains(equipment)
                            ) {
                                toggle(equipment, in: &selectedEquipment)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            markRecent(exercise)
            if let onPick {
                onPick(exercise)
                dismiss()
            } else {
                selectedExercise = exercise
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(exercise.equipment.displayName)
                    Text("·")
                    Text(exercise.primaryMuscle.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func markRecent(_ exercise: Exercise) {
        var ids = recentIDs.filter { $0 != exercise.id }
        ids.insert(exercise.id, at: 0)
        recentIDsRaw = ids.prefix(10).map(\.uuidString).joined(separator: ",")
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .modelContainer(for: [Exercise.self], inMemory: true)
}
