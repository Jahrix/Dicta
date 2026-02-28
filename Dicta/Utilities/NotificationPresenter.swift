import Foundation
import UserNotifications

final class NotificationPresenter {
    static let shared = NotificationPresenter()
    private var hasRequestedAuthorization = false

    private init() {}

    func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
