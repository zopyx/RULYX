import UIKit
import UserNotifications

final class BlueskyAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(
            name: .pushTokenDidUpdate,
            object: nil,
            userInfo: ["deviceToken": deviceToken]
        )
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(
            name: .pushRegistrationDidFail,
            object: nil,
            userInfo: ["error": error]
        )
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(
            name: .pushNotificationDidReceive,
            object: nil,
            userInfo: ["payload": userInfo]
        )
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(
            name: .pushNotificationDidReceive,
            object: nil,
            userInfo: ["payload": notification.request.content.userInfo]
        )
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(
            name: .pushNotificationDidOpen,
            object: nil,
            userInfo: ["payload": response.notification.request.content.userInfo]
        )
        completionHandler()
    }
}

extension Notification.Name {
    static let pushTokenDidUpdate = Notification.Name("pushTokenDidUpdate")
    static let pushRegistrationDidFail = Notification.Name("pushRegistrationDidFail")
    static let pushNotificationDidReceive = Notification.Name("pushNotificationDidReceive")
    static let pushNotificationDidOpen = Notification.Name("pushNotificationDidOpen")
}
