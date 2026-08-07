import SwiftUI

/// PRD §7.5: "In-app banner for 4 seconds if foregrounded" — same content
/// shape as the notification (`RestNotificationScheduler.Content`), just
/// rendered over the workout screen instead of the system notification
/// center. Tapping dismisses it early; `ActiveWorkoutView` also auto-clears
/// it after ~4s.
struct RestCompleteBanner: View {
    let content: RestNotificationScheduler.Content
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest complete — \(RestNotificationScheduler.formattedClock(content.durationSeconds))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    if let nextLine = content.nextLine {
                        Text("Next: \(nextLine)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
