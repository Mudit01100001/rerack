import SwiftUI

/// PRD §9.6. The dashboard tiles (Statistics, Exercises, Measures, Calendar)
/// ship in M6–M9; M1 shows the shape of the screen only.
struct ProfileView: View {
    @AppStorage(AppearanceStorageKey.value) private var appearanceModeRaw = AppearanceMode.system.rawValue

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

                Section("Dashboard") {
                    dashboardRow("Statistics", systemImage: "chart.bar")
                    dashboardRow("Exercises", systemImage: "list.bullet")
                    dashboardRow("Measures", systemImage: "scalemass")
                    dashboardRow("Calendar", systemImage: "calendar")
                }
            }
            .navigationTitle("Profile")
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
}
