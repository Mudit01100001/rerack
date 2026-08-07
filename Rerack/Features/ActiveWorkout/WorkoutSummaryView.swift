import SwiftUI
import SwiftData
import PhotosUI

/// PRD §9.4. Presented after `Finish`, before the workout is dismissed back
/// to the tab bar. By the time this appears, `ActiveWorkoutView.finish()` has
/// already set `endedAt`, run `PersonalRecordDetector`, and updated the
/// routine baseline (§13.4, §9.3) — so this screen's 🏆 flags and record
/// count are already correct, and `Done` only needs to persist the optional
/// context (photo/gym/tags/notes) added here.
struct WorkoutSummaryView: View {
    @Bindable var workout: Workout
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var newTagText = ""

    private var sortedExercises: [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Looked up rather than recomputed — `PersonalRecordDetector` has
    /// already run and written these rows by the time this screen appears.
    private var newRecordCount: Int {
        let workoutID = workout.id
        let descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.sourceWorkoutID == workoutID })
        return (try? modelContext.fetch(descriptor))?.count ?? 0
    }

    private var locationBinding: Binding<String> {
        Binding(get: { workout.location ?? "" }, set: { workout.location = $0.isEmpty ? nil : $0 })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { workout.notes ?? "" }, set: { workout.notes = $0.isEmpty ? nil : $0 })
    }

    /// Previously-used gym values across every other workout, most-used
    /// first (PRD §9.4: "free text with autocomplete from prior values,
    /// defaulting to your most-used").
    private var previousLocations: [String] {
        distinctValues { $0.location.map { [$0] } ?? [] }
    }

    private var previousTags: [String] {
        distinctValues(\.tags)
    }

    /// Previously-used tags plus anything already on this workout, de-duped
    /// in encounter order, so a tag just typed into the "new tag" field shows
    /// up as a selected chip immediately rather than living only in the text field.
    private var allTagOptions: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for tag in workout.tags + previousTags where !seen.contains(tag) {
            seen.insert(tag)
            ordered.append(tag)
        }
        return ordered
    }

    private func distinctValues(_ extract: (Workout) -> [String]) -> [String] {
        let workoutID = workout.id
        let all = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
        var counts: [String: Int] = [:]
        for other in all where other.id != workoutID {
            for value in extract(other) where !value.isEmpty {
                counts[value, default: 0] += 1
            }
        }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    photoPicker
                    statTiles
                    dateLine
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        gymField
                        tagsField
                        notesField
                    }
                    Divider()
                    exerciseBreakdown
                    if newRecordCount > 0 {
                        Text("🏆 \(newRecordCount) new record\(newRecordCount == 1 ? "" : "s") this session")
                            .font(.subheadline.bold())
                    }
                    actionButtons
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: photoItem) {
                guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                // Replace, don't accumulate — PRD §9.4 is one photo per workout.
                if let oldFilename = workout.photoFilename { PhotoStorage.delete(oldFilename) }
                photoData = data
                workout.photoFilename = PhotoStorage.save(data)
            }
            .onAppear {
                if let filename = workout.photoFilename {
                    photoData = try? Data(contentsOf: PhotoStorage.url(for: filename))
                }
                if workout.location == nil, let mostUsed = previousLocations.first {
                    workout.location = mostUsed
                }
            }
        }
    }

    // MARK: - Header, photo, stats

    private var greeting: String {
        let name = currentProfile()?.displayName ?? ""
        return name.isEmpty ? "🎉 Good job!" : "🎉 Good job, \(name)!"
    }

    private func currentProfile() -> UserProfile? {
        (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(greeting).font(.title2.bold())
            Text(workout.routineNameSnapshot ?? workout.title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    /// PRD §9.4: photo sits at the top, one image, PhotosPicker with camera
    /// and library — reusing the exact `PhotoStorage` utility Cardio already
    /// uses (`AddCardioSessionView`), not a second photo pipeline.
    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.largeTitle)
                    Text("Add a photo")
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            statTile(value: formattedDuration, label: "Duration")
            statTile(value: "\(Int(workout.cachedVolumeKg)) kg", label: "Volume")
            statTile(value: "\(workout.cachedSetCount)", label: "Sets")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// PRD §18 Q7: pure wall-clock `endedAt − startedAt`, no exceptions —
    /// `endedAt` is already set by the time this screen exists.
    private var formattedDuration: String {
        let interval = (workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt)
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private var dateLine: some View {
        // PRD §9.4: auto-captured, displayed, not editable.
        Text(workout.startedAt.formatted(date: .complete, time: .shortened))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Gym / tags / notes

    private var gymField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Gym", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Gym", text: locationBinding)
                .textFieldStyle(.roundedBorder)
            if !previousLocations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(previousLocations, id: \.self) { location in
                            FilterChip(title: location, isSelected: workout.location == location) {
                                workout.location = location
                            }
                        }
                    }
                }
            }
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tags", systemImage: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !allTagOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(allTagOptions, id: \.self) { tag in
                            FilterChip(title: tag, isSelected: workout.tags.contains(tag)) {
                                toggleTag(tag)
                            }
                        }
                    }
                }
            }
            HStack {
                TextField("New tag", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewTag)
                Button("Add", action: addNewTag)
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if let index = workout.tags.firstIndex(of: tag) {
            workout.tags.remove(at: index)
        } else {
            workout.tags.append(tag)
        }
    }

    private func addNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !workout.tags.contains(trimmed) else { return }
        workout.tags.append(trimmed)
        newTagText = ""
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notes", systemImage: "note.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Optional", text: notesBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }

    // MARK: - Exercise breakdown & actions

    private var exerciseBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercise breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(sortedExercises) { workoutExercise in
                let completed = (workoutExercise.sets ?? []).filter(\.isCompleted)
                if !completed.isEmpty {
                    exerciseRow(workoutExercise, completed: completed)
                }
            }
        }
    }

    private func exerciseRow(_ workoutExercise: WorkoutExercise, completed: [SetLog]) -> some View {
        let volume = completed.reduce(0) { $0 + $1.setVolumeKg }
        let hasPR = completed.contains { !$0.prFlags.isEmpty }
        return HStack {
            HStack(spacing: 6) {
                if let label = SupersetGrouping.label(for: workoutExercise, among: sortedExercises) {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Text(workoutExercise.exercise?.name ?? "Exercise")
            }
            Spacer()
            Text("\(completed.count) sets · \(Int(volume)) kg")
                .foregroundStyle(.secondary)
            if hasPR {
                Text("🏆")
            }
        }
        .font(.subheadline)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // PRD §9.5 — the share carousel is M10. Disabled stub only, per scope.
            Button("Share") {}
                .buttonStyle(.bordered)
                .disabled(true)
            Button("Done") {
                try? modelContext.save()
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
