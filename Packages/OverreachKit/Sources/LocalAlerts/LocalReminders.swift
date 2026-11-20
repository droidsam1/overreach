import Domain
import Foundation
import UserNotifications

/// One-off reminders at a date (e.g. the Garmin key about to expire). Permission is requested the first time one is
/// scheduled; if it is refused, Settings still shows the warning.
public struct LocalReminders: LocalReminderScheduler {
    public init() {}

    public func schedule(id: String, at date: Date, title: String, body: String) async {
        guard date > Date() else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Same identifier: replaces the reminder scheduled before (e.g. for the previous key).
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    public func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
