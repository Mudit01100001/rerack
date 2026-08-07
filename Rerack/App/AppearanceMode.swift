import SwiftUI

/// User-facing override of system light/dark mode. Stored in UserDefaults
/// (not SwiftData) since it's a device-local display preference, not data —
/// consistent with PRD §10.2 General settings.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "follow the system setting" — SwiftUI's own default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppearanceStorageKey {
    static let value = "com.mudit.logbook.appearanceMode"
}
