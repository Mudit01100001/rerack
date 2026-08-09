import SwiftUI
import SwiftData
import PhotosUI

/// PRD §21: manual entry is the primary, always-available path. Photo attach
/// is a plain visual record only — nothing reads numbers off it yet (that's
/// the on-device OCR research in PRD §22), so it never blocks manual entry
/// and never substitutes for it.
struct AddCardioSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var activity: CardioActivity = .treadmill
    @State private var startedAt = Date()
    @State private var durationMinutesText = ""
    @State private var distanceKmText = ""
    @State private var caloriesText = ""
    @State private var inclineText = ""
    @State private var resistanceText = ""
    @State private var notes = ""

    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    private var showsIncline: Bool { activity == .treadmill }
    private var showsResistance: Bool { [.bike, .rower, .elliptical].contains(activity) }

    private var canSave: Bool {
        !durationMinutesText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        // Computed here, in the MainActor-isolated body getter, and captured
        // by value below — PhotosPicker's `label` closure parameter isn't
        // declared @MainActor in the SDK, so reading the @State property
        // directly from inside that closure trips Swift 6 strict concurrency
        // even though it only ever runs on the main thread in practice.
        let attachPhotoLabel = photoData == nil ? "Attach a photo" : "Photo attached"

        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $activity) {
                        ForEach(CardioActivity.allCases) { item in
                            Label(item.displayName, systemImage: item.systemImage).tag(item)
                        }
                    }
                    DatePicker("Date", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Numbers") {
                    TextField("Duration (minutes)", text: $durationMinutesText)
                        .keyboardType(.numberPad)
                    TextField("Distance (km)", text: $distanceKmText)
                        .keyboardType(.decimalPad)
                    TextField("Calories", text: $caloriesText)
                        .keyboardType(.numberPad)
                    if showsIncline {
                        TextField("Incline (%)", text: $inclineText)
                            .keyboardType(.decimalPad)
                    }
                    if showsResistance {
                        TextField("Resistance level", text: $resistanceText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(attachPhotoLabel, systemImage: "camera")
                    }
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                    }
                } footer: {
                    Text("Saved for your own record, auto-reading the numbers off it isn't built yet.")
                }
            }
            .navigationTitle("Log Cardio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .task(id: photoItem) {
                if let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private func save() {
        let minutes = Double(durationMinutesText) ?? 0
        let session = CardioSession(
            activity: activity,
            startedAt: startedAt,
            durationSec: Int(minutes * 60)
        )
        session.distanceMeters = Double(distanceKmText).map { $0 * 1000 }
        session.caloriesKcal = Double(caloriesText)
        session.inclinePercent = showsIncline ? Double(inclineText) : nil
        session.resistanceLevel = showsResistance ? Double(resistanceText) : nil
        session.notes = notes.isEmpty ? nil : notes
        if let photoData {
            session.photoFilename = PhotoStorage.save(photoData)
        }

        modelContext.insert(session)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AddCardioSessionView()
        .modelContainer(for: [CardioSession.self], inMemory: true)
}
