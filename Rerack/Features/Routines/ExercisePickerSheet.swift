import SwiftUI

/// Thin modal wrapper around `ExerciseLibraryView` in pick mode, so the
/// routine editor (M2) gets the same search/filter/recent experience as
/// browsing the library directly (M1) rather than a second, worse picker.
struct ExercisePickerSheet: View {
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            ExerciseLibraryView(onPick: onPick)
        }
    }
}
