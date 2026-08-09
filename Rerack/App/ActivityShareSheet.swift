import SwiftUI
import UIKit

/// Thin `UIActivityViewController` wrapper for `.sheet(isPresented:)`
/// presentation. `ShareLink` needs a concrete `Transferable` item at view
/// construction time, which doesn't fit "generate a file when the button is
/// tapped, then share it" — CSV export (§14) and, from M10, the share-card
/// carousel's "More…" action (§9.5) both need exactly that.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
