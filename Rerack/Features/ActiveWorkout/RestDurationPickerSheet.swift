import SwiftUI

/// PRD §7.5: "Picker: wheel from 0:05 to 10:00 in 5s steps, plus chips 0:30 ·
/// 1:00 · 1:30 · 2:00 · 3:00 · 5:00." Shared by the exercise card's rest
/// config (per-exercise-in-workout override / per-exercise default) and the
/// Settings → Workout "Default rest time" row — one wheel, one set of chips,
/// rather than two near-identical pickers drifting apart.
struct RestDurationPicker: View {
    @Binding var seconds: Int

    private static let chipValues = [30, 60, 90, 120, 180, 300]
    private static let wheelValues = Array(stride(from: 5, through: 600, by: 5))

    var body: some View {
        VStack(spacing: 16) {
            Picker("Rest duration", selection: $seconds) {
                ForEach(Self.wheelValues, id: \.self) { value in
                    Text(RestNotificationScheduler.formattedClock(value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            HStack(spacing: 8) {
                ForEach(Self.chipValues, id: \.self) { value in
                    Button(RestNotificationScheduler.formattedClock(value)) { seconds = value }
                        .buttonStyle(.bordered)
                        .tint(seconds == value ? Color.accentColor : Color.secondary)
                }
            }
        }
    }
}

/// Wraps `RestDurationPicker` in a medium-detent sheet with Save/Cancel, plus
/// an optional "save as default" toggle for the exercise-card case (PRD
/// §7.5's hierarchy: per-exercise-in-workout override vs. per-exercise
/// default — see `ActiveWorkoutView.applyRestConfig`). The Settings usage
/// passes `saveAsDefaultLabel: nil` since there's only one thing to set there.
struct RestDurationPickerSheet: View {
    let title: String
    let saveAsDefaultLabel: String?
    let onSave: (_ seconds: Int, _ saveAsDefault: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seconds: Int
    @State private var saveAsDefault: Bool

    init(
        title: String,
        saveAsDefaultLabel: String? = nil,
        initialSeconds: Int,
        initialSaveAsDefault: Bool = false,
        onSave: @escaping (Int, Bool) -> Void
    ) {
        self.title = title
        self.saveAsDefaultLabel = saveAsDefaultLabel
        self.onSave = onSave
        _seconds = State(initialValue: initialSeconds)
        _saveAsDefault = State(initialValue: initialSaveAsDefault)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                RestDurationPicker(seconds: $seconds)
                if let saveAsDefaultLabel {
                    Toggle(saveAsDefaultLabel, isOn: $saveAsDefault)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(seconds, saveAsDefault)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
