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
    @State private var showingShareCards = false
    @State private var showingConfetti = false

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

    /// Everything fits one screen with no scrolling until you actually add
    /// content — collapsed rows rather than expanded boxes, and the exercise
    /// breakdown behind a disclosure instead of always-on. A finish screen
    /// you have to scroll to reach "Done" on is a finish screen that gets
    /// dismissed without its optional fields ever being filled.
    /// This screen is the *input* step: notes, photo, gym, tags. The
    /// celebration and the summary belong to what comes after saving, not
    /// here — confetti over a form you're still filling in rushes you past
    /// the fields, and the payoff lands better once the work is actually
    /// committed.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    statTiles
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                }

                Section {
                    photoRow
                    gymRow
                    tagsRow
                    notesRow
                    dateRow
                }

                Section {
                    DisclosureGroup {
                        exerciseBreakdown
                    } label: {
                        HStack {
                            Text("Exercise breakdown")
                            Spacer()
                            Text("\(sortedExercises.count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if newRecordCount > 0 {
                        Label(
                            "\(newRecordCount) new record\(newRecordCount == 1 ? "" : "s") this session",
                            systemImage: "trophy.fill"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    actionButtons
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: photoItem) {
                guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                // Replace, don't accumulate — PRD §9.4 is one photo per workout.
                if let oldFilename = workout.photoFilename { PhotoStorage.delete(oldFilename) }
                photoData = data
                workout.photoFilename = PhotoStorage.save(data)
            }
            // Full screen, not a sheet: saving is the end of the session, so
            // what follows should feel like arriving somewhere rather than a
            // panel over unfinished business.
            .fullScreenCover(isPresented: $showingShareCards) {
                WorkoutCompleteView(workout: workout, onDone: onDone)
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
        VStack(spacing: 2) {
            Text(greeting).font(.title3.bold())
            Text(workout.routineNameSnapshot ?? workout.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }

    /// PRD §9.4: photo sits at the top, one image, PhotosPicker with camera
    /// and library — reusing the exact `PhotoStorage` utility Cardio already
    /// uses (`AddCardioSessionView`), not a second photo pipeline.
    /// Collapsed to a row until a photo exists — a 180pt dashed box costs a
    /// third of the screen to advertise an optional field most sessions skip.
    private var photoRow: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            HStack {
                Label("Photo", systemImage: "camera")
                Spacer()
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("Add").foregroundStyle(.secondary)
                }
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
        .listRowBackground(Color.clear)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// PRD §18 Q7: pure wall-clock `endedAt − startedAt`, no exceptions —
    /// `endedAt` is already set by the time this screen exists.
    private var formattedDuration: String {
        let interval = (workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt)
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private var dateRow: some View {
        // PRD §9.4: auto-captured, displayed, not editable.
        HStack {
            Label("Date", systemImage: "calendar")
            Spacer()
            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gym / tags / notes

    /// Each optional field is one row that grows only when used. The
    /// autocomplete chips appear under Gym once you focus it, not before —
    /// they're an accelerator, not something to look at every session.
    private var gymRow: some View {
        HStack {
            Label("Gym", systemImage: "mappin.and.ellipse")
            Spacer()
            TextField("Select", text: locationBinding)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }

    private var tagsRow: some View {
        NavigationLink {
            tagPicker
        } label: {
            HStack {
                Label("Tags", systemImage: "tag")
                Spacer()
                Text(workout.tags.isEmpty ? "None" : workout.tags.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var tagPicker: some View {
        List {
            Section {
                HStack {
                    TextField("New tag", text: $newTagText)
                        .onSubmit(addNewTag)
                    Button("Add", action: addNewTag)
                        .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !allTagOptions.isEmpty {
                Section {
                    ForEach(allTagOptions, id: \.self) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            HStack {
                                Text(tag).foregroundStyle(.primary)
                                Spacer()
                                if workout.tags.contains(tag) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
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

    private var notesRow: some View {
        HStack(alignment: .top) {
            Label("Notes", systemImage: "note.text")
            Spacer()
            // Grows from one line only as you type — an always-3-line box
            // costs vertical space every session to serve the rare one.
            TextField("Optional", text: notesBinding, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .lineLimit(1...4)
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

    /// One action. Sharing used to sit beside Done as an equal choice, which
    /// meant you could leave without ever seeing your own summary. Saving now
    /// leads into it, and sharing is a choice you make from there.
    private var actionButtons: some View {
        Button {
            try? modelContext.save()
            showingShareCards = true
        } label: {
            Text("Save Workout")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .listRowBackground(Color.clear)
    }
}
