import Foundation
import UserNotifications

/// PRD §7.5: the local notification fired when rest completes while the app
/// is backgrounded or the screen is locked. Scheduled the moment rest starts
/// (so the OS fires it at the right wall-clock instant even if the app is
/// later suspended, matching the wall-clock-not-tick-counter requirement in
/// §17), and cancelled on every path that ends a rest period early —
/// `ActiveWorkoutView.clearRest()` is the single funnel all of those go
/// through, so cancellation lives there, not scattered across call sites.
@MainActor
enum RestNotificationScheduler {
    private static let requestIdentifier = "com.mudit.logbook.restComplete"
    private static let hasAskedPermissionKey = "com.mudit.logbook.hasAskedRestNotificationPermission"

    struct Content {
        let durationSeconds: Int
        /// "Seated Cable Row · Set 3 · 12 kg × 5", already formatted — nil if
        /// there's genuinely nothing next (end of workout).
        let nextLine: String?
    }

    /// Replaces any previously-scheduled rest notification — callers never
    /// need to cancel first, which matters for the "duration adjusted"
    /// re-schedule path (§7.5) where the old trigger time is simply wrong.
    static func schedule(fireAt: Date, content: Content) {
        cancelPending()
        let notification = UNMutableNotificationContent()
        notification.title = "Rest complete, \(formattedClock(content.durationSeconds))"
        notification.body = content.nextLine.map { "Next: \($0)" } ?? "Time to get back to it."
        notification.sound = .default

        // At least 1s out — a trigger interval of 0 is rejected by
        // UNTimeIntervalNotificationTrigger.
        let interval = max(fireAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: notification, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Un-ticking the set that started rest, skipping the timer, adjusting
    /// its duration, changing the exercise's rest config mid-rest, removing
    /// the exercise, or finishing/discarding the workout all funnel through
    /// `clearRest()`, which calls this — the PRD-named failure mode is a
    /// stale notification firing after the user has already moved on.
    static func cancelPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    /// PRD §7.5: permission is asked exactly once — the first time a rest
    /// timer is discovered to have completed while the app was backgrounded
    /// — and never again regardless of the answer. `onNeedsPrimer` is called
    /// back on the main actor only when the one-line explanation should be
    /// shown before the system prompt; the "asked" flag is set at that same
    /// moment, not on the button tap, so declining the system dialog later
    /// can't re-open the question.
    static func handleBackgroundedCompletion(onNeedsPrimer: @escaping @MainActor () -> Void) {
        guard !UserDefaults.standard.bool(forKey: hasAskedPermissionKey) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor in
                UserDefaults.standard.set(true, forKey: hasAskedPermissionKey)
                onNeedsPrimer()
            }
        }
    }

    static func requestSystemPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func formattedClock(_ totalSeconds: Int) -> String {
        let clamped = max(totalSeconds, 0)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
