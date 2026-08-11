import SwiftUI

/// PRD §10.1/§10.2. Which side the tick button sits on in a set row.
///
/// Passed through the environment rather than read from `UserProfile` at each
/// site: `SetRowView` is rendered dozens of times per screen and shouldn't
/// each hold a SwiftData query, and onboarding needs to override it locally
/// to show a live preview of a choice that hasn't been saved yet.
private struct DominantHandKey: EnvironmentKey {
    static let defaultValue: DominantHand = .right
}

extension EnvironmentValues {
    var dominantHand: DominantHand {
        get { self[DominantHandKey.self] }
        set { self[DominantHandKey.self] = newValue }
    }
}
