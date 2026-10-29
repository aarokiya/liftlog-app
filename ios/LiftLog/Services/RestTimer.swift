import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class RestTimer {
    private static let notificationId = "rest-timer"
    private(set) var endsAt: Date?
    private(set) var duration: TimeInterval = 0
    private var askedPermission = false

    func start(seconds: Int) {
        duration = TimeInterval(seconds)
        endsAt = .now.addingTimeInterval(duration)
        schedule()
    }

    func add(_ seconds: Int) {
        guard let endsAt else { return }
        let newEnd = endsAt.addingTimeInterval(TimeInterval(seconds))
        self.endsAt = max(newEnd, .now)
        duration = max(0, duration + TimeInterval(seconds))
        schedule()
    }

    func stop() {
        endsAt = nil
        schedule()
    }

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        guard let endsAt, endsAt > .now else { return }
        if !askedPermission {
            askedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endsAt.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger))
    }
}
