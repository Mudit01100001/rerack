import SwiftUI
import SwiftData

/// PRD §9.6. The dashboard tiles (Statistics, Exercises, Measures, Calendar)
/// ship in M6–M9; M1 shows the shape of the screen only.
struct ProfileView: View {
    @AppStorage(AppearanceStorageKey.value) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    /// PRD §10.1: onboarding (which would normally create this row) hasn't
    /// shipped yet, so Settings is the first place a `UserProfile` might get
    /// created — done lazily here rather than at app launch, matching "one
    /// row is expected to exist" without forcing a migration step.
    @State private var ensuredProfile: UserProfile?
    @State private var showingRestPicker = false

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppIdentity.displayName)
                            .font(.title2.bold())
                        Text("Statistics, calendar, and measures ship in M6–M9.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Preferences") {
                    Picker("Appearance", selection: appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                if let profile = ensuredProfile {
                    workoutSection(profile)
                }

                Section("Dashboard") {
                    dashboardRow("Statistics", systemImage: "chart.bar")
                    dashboardRow("Exercises", systemImage: "list.bullet")
                    dashboardRow("Measures", systemImage: "scalemass")
                    dashboardRow("Calendar", systemImage: "calendar")
                }
            }
            .navigationTitle("Profile")
        }
        .task { ensureProfile() }
    }

    /// PRD §10.2 Workout section.
    private func workoutSection(_ profile: UserProfile) -> some View {
        Section("Workout") {
            Button {
                showingRestPicker = true
            } label: {
                HStack {
                    Text("Default rest time")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(RestNotificationScheduler.formattedClock(profile.defaultRestSeconds))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingRestPicker) {
                RestDurationPickerSheet(
                    title: "Default Rest Time",
                    initialSeconds: profile.defaultRestSeconds,
                    onSave: { seconds, _ in profile.defaultRestSeconds = seconds }
                )
            }

            Toggle("Rest timer sound", isOn: Binding(
                get: { profile.restTimerSoundEnabled },
                set: { profile.restTimerSoundEnabled = $0 }
            ))
            Toggle("Auto-start rest timer", isOn: Binding(
                get: { profile.autoStartRestTimer },
                set: { profile.autoStartRestTimer = $0 }
            ))
            Toggle("Keep screen awake during workout", isOn: Binding(
                get: { profile.keepScreenAwakeDuringWorkout },
                set: { profile.keepScreenAwakeDuringWorkout = $0 }
            ))
        }
    }

    private func ensureProfile() {
        if let existing = profiles.first {
            ensuredProfile = existing
        } else {
            let created = UserProfile()
            modelContext.insert(created)
            try? modelContext.save()
            ensuredProfile = created
        }
    }

    private func dashboardRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("Soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
