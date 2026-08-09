import SwiftUI
import SwiftData
import Photos

/// PRD §9.5. The share carousel: paged card variants, then the export
/// actions. Reached from the finish screen's `Share` button.
struct ShareCardSheet: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var variant: ShareCardView.Variant = .animal
    @State private var size: ShareCardView.Size = .story
    @State private var renderedURL: URL?
    @State private var showingShareSheet = false
    @State private var saveMessage: String?

    private var content: ShareCardContent {
        ShareCardContentBuilder.build(for: workout, context: modelContext)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // The card lays out at a fixed point size so `ImageRenderer`
                // gets identical geometry to what's previewed. Scaling to fit
                // here — rather than making the card adapt to the sheet —
                // keeps the preview an exact preview of the exported file.
                GeometryReader { geometry in
                    let scale = min(
                        geometry.size.width / size.points.width,
                        geometry.size.height / size.points.height,
                        1
                    )
                    TabView(selection: $variant) {
                        ForEach(ShareCardView.Variant.allCases) { option in
                            ShareCardView(variant: option, size: size, content: content)
                                .scaleEffect(scale)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .tag(option)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
                .frame(maxHeight: .infinity)

                Picker("Size", selection: $size) {
                    Text("Story").tag(ShareCardView.Size.story)
                    Text("Square").tag(ShareCardView.Size.square)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack(spacing: 10) {
                    // Only offered when Instagram is actually installed —
                    // a button that opens the App Store instead of doing the
                    // thing it names is worse than not showing it.
                    if InstagramStoryShare.isAvailable {
                        actionButton("Stories", systemImage: "camera.circle") { shareToInstagram() }
                    }
                    actionButton("Save", systemImage: "square.and.arrow.down") { saveToPhotos() }
                    actionButton("Copy", systemImage: "doc.on.doc") { copyText() }
                    actionButton("More", systemImage: "square.and.arrow.up") { shareImage() }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let renderedURL {
                    ActivityShareSheet(items: [renderedURL])
                }
            }
            .alert("Saved", isPresented: Binding(
                get: { saveMessage != nil },
                set: { if !$0 { saveMessage = nil } }
            )) {
                Button("OK") { saveMessage = nil }
            } message: {
                Text(saveMessage ?? "")
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Actions

    @MainActor
    private func render() -> URL? {
        let renderer = ImageRenderer(content: ShareCardView(variant: variant, size: size, content: content))
        // The card lays out in points at 1/3 scale; rendering at 3× gives the
        // 1080-wide asset §9.5 asks for without duplicating the layout maths.
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppIdentity.csvExportPrefix)-\(variant.rawValue).png")
        try? data.write(to: url)
        return url
    }

    private func shareImage() {
        renderedURL = render()
        showingShareSheet = renderedURL != nil
    }

    /// Hands the card to Instagram's story composer. Nothing is posted — the
    /// user still composes and shares inside Instagram — so this needs no
    /// confirmation beyond the tap that started it.
    private func shareToInstagram() {
        // Stories are 1080×1920; handing over a square card would letterbox.
        let previousSize = size
        size = .story
        defer { size = previousSize }
        guard let url = render(), let image = UIImage(contentsOfFile: url.path) else { return }
        if !InstagramStoryShare.share(backgroundImage: image) {
            saveMessage = "Couldn't open Instagram."
        }
    }

    /// Requests add-only Photos access — the app never reads the library, so
    /// asking for full access would be asking for more than it uses.
    private func saveToPhotos() {
        guard let url = render(), let image = UIImage(contentsOfFile: url.path) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in saveMessage = "Photos access wasn't granted. Use Share instead." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    saveMessage = success ? "Card saved to Photos." : "Couldn't save the card."
                }
            }
        }
    }

    private func copyText() {
        UIPasteboard.general.string = ShareCardContentBuilder.plainText(for: workout, context: modelContext)
        saveMessage = "Workout copied as text."
    }
}

/// Resolves a workout into everything the cards render, once.
@MainActor
enum ShareCardContentBuilder {
    static func build(for workout: Workout, context: ModelContext) -> ShareCardContent {
        let exercises = (workout.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let completed = exercises.flatMap { $0.sets ?? [] }.filter(\.isCompleted)
        let volume = completed.reduce(0) { $0 + $1.setVolumeKg }

        let muscleTotals = ProfileStats.volumeByMuscle([workout])
        let heaviest = muscleTotals.first?.volumeKg ?? 0
        let breakdown = muscleTotals.prefix(6).map {
            ShareCardContent.MuscleEntry(
                name: $0.muscle.displayName,
                fraction: heaviest > 0 ? $0.volumeKg / heaviest : 0
            )
        }

        let lines: [String] = exercises.compactMap { workoutExercise in
            let sets = (workoutExercise.sets ?? []).filter(\.isCompleted)
            guard !sets.isEmpty, let name = workoutExercise.exercise?.name else { return nil }
            let setVolume = sets.reduce(0) { $0 + $1.setVolumeKg }
            return "\(name) — \(sets.count) × \(Int(setVolume)) kg"
        }

        let match = AnimalLadder.match(volumeKg: volume)
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first

        let prCount: Int = {
            let workoutID = workout.id
            let descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.sourceWorkoutID == workoutID })
            return (try? context.fetch(descriptor))?.count ?? 0
        }()

        return ShareCardContent(
            workoutTitle: workout.routineNameSnapshot ?? workout.title,
            dateLine: workout.startedAt.formatted(date: .abbreviated, time: .shortened),
            durationFormatted: formattedDuration(ProfileStats.duration(of: workout)),
            volumeKgFormatted: Int(volume).formatted(),
            setCount: completed.count,
            prCount: prCount,
            exerciseLines: lines,
            muscleBreakdown: Array(breakdown),
            animalComparison: match?.headline,
            animalProgress: match.flatMap { m in
                m.progressLabel.map { ShareCardContent.AnimalProgress(fraction: m.progressToNext, label: $0) }
            },
            animalAssetName: match?.animal.assetName,
            username: profile?.username
        )
    }

    /// §9.5 "Copy as text" — the whole session, plain, for pasting anywhere.
    static func plainText(for workout: Workout, context: ModelContext) -> String {
        let content = build(for: workout, context: context)
        var lines = [
            content.workoutTitle,
            content.dateLine,
            "\(content.durationFormatted) · \(content.volumeKgFormatted) kg · \(content.setCount) sets",
            "",
        ]
        lines.append(contentsOf: content.exerciseLines)
        if let comparison = content.animalComparison {
            lines.append("")
            lines.append("That's \(comparison)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formattedDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
