import Domain
import Foundation
import UserNotifications

/// Tells the user the rest ended while the app is in the background. iOS does not show these notifications while
/// the app is open, where the timer is already visible. Permission is requested the first time a rest starts.
public struct LocalRestAlerts: RestAlertScheduler {
    private static let identifier = "rest-timer-end"

    public init() {}

    public func scheduleRestEnd(at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        // Same identifier: replaces the alert of the previous rest.
        try? await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    public func cancelRestEnd() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}
