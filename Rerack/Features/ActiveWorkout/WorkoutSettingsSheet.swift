import SwiftUI
import SwiftData

/// Settings that apply to *this session*, reachable from the bottom of the
/// active-workout screen. Deliberately narrow: anything that outlives the
/// session belongs in Profile → Settings (§10.2), and duplicating it here
/// would create two places to change one thing.
struct WorkoutSettingsSheet: View {
    @Bindable var workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var showingRestPicker = false

    private var profile: UserProfile? { profiles.first }

    private var titleBinding: Binding<String> {
        Binding(get: { workout.title }, set: { workout.title = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This workout") {
                    TextField("Workout name", text: titleBinding)

                    Toggle("Count toward progress", isOn: Binding(
                        get: { workout.trackedAsProgress },
                        set: { workout.trackedAsProgress = $0 }
                    ))
                }
                // §9.3: a deload or a testing session still logs and exports
                // — it just never touches PRs or progress graphs. Saying so
                // here beats leaving people to infer it from a toggle label.
                Section {
                } footer: {
                    Text("Turning this off still logs and exports the workout, it just won't set records or move your progress graphs.")
                }

                if let profile {
                    Section("Rest timer") {
                        Button {
                            showingRestPicker = true
                        } label: {
                            HStack {
                                Text("Default rest time").foregroundStyle(.primary)
                                Spacer()
                                Text(RestNotificationScheduler.formattedClock(profile.defaultRestSeconds))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Auto-start rest timer", isOn: Binding(
                            get: { profile.autoStartRestTimer },
                            set: { profile.autoStartRestTimer = $0 }
                        ))
                        Toggle("Rest timer sound", isOn: Binding(
                            get: { profile.restTimerSoundEnabled },
                            set: { profile.restTimerSoundEnabled = $0 }
                        ))
                    }

                    Section {
                        Toggle("Keep screen awake", isOn: Binding(
                            get: { profile.keepScreenAwakeDuringWorkout },
                            set: { profile.keepScreenAwakeDuringWorkout = $0 }
                        ))
                    }
                }
            }
            .navigationTitle("Workout Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRestPicker) {
                if let profile {
                    RestDurationPickerSheet(
                        title: "Default Rest Time",
                        initialSeconds: profile.defaultRestSeconds,
                        onSave: { seconds, _ in profile.defaultRestSeconds = seconds }
                    )
                }
            }
        }
    }
}
