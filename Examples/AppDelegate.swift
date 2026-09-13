import UIKit
import PushPort

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do {
            try PushPort.shared.initialize(appId: "YOUR_PUSHPORT_APP_ID", environment: .sandbox)
        } catch {
            // Display a configuration error in your test application's UI.
            assertionFailure(error.localizedDescription)
        }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        PushPort.shared.didRegisterForRemoteNotifications(deviceToken: token)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushPort.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}

// SwiftUI hosts: @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
// Request permission from a button with Task { try await PushPort.shared.requestPermission() }.
