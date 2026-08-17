import SwiftUI

/// A quiet confirmation that something good happened.
///
/// Replaces the `.alert` that used to confirm a share-card save. An alert is
/// the system's vocabulary for *stop and decide* — modal, centred, dimming
/// everything behind it, requiring an OK. Using it to say "saved" made a
/// small success read as a warning, and the response it triggered was alarm
/// rather than satisfaction. This says the same thing from the top of the
/// screen and leaves on its own.
struct Toast: Equatable {
    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = .green

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.message == rhs.message && lhs.systemImage == rhs.systemImage
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    banner(toast)
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .animation(.snappy(duration: 0.3), value: toast)
            .onChange(of: toast) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(2.2))
                    guard !Task.isCancelled else { return }
                    toast = nil
                }
            }
    }

    private func banner(_ toast: Toast) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(toast.tint)
                .dsFont(DS.TypeScale.body, relativeTo: .body, weight: .semibold)
            Text(toast.message)
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline, weight: .medium)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.top, DS.Space.xs)
        // Nothing to tap and nothing to read for longer than it takes to
        // glance — it must not sit in front of the card underneath it.
        .allowsHitTesting(false)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
