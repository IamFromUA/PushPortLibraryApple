#if os(iOS)
import UserNotifications

/// Strongly retained by the SDK, forwards to the host's weak delegate without swizzling.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var owner: PushPort?
    private weak var forwarding: UNUserNotificationCenterDelegate?
    @MainActor init(owner: PushPort, forwarding: UNUserNotificationCenterDelegate?) {
        self.owner = owner; self.forwarding = forwarding
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { completionHandler([]); return }
            let ours = self.owner?.recognizes(notification) == true
            if ours && self.owner?.status?.subscribed == false { completionHandler([]); return }
            if let forwarding, forwarding.responds(to: #selector(userNotificationCenter(_:willPresent:withCompletionHandler:))) {
                forwarding.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            } else { completionHandler(ours ? [.banner, .list, .sound] : []) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            _ = self?.owner?.handleNotificationResponse(response)
            if let forwarding = self?.forwarding,
               forwarding.responds(to: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                forwarding.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else { completionHandler() }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        forwarding?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}
#endif
