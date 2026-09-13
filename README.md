# PushPort Apple SDK

Native Swift SDK for iOS push subscriptions, device metadata and notification interactions. Distributed as a normal Swift package. No Firebase dependency, account credentials or Google configuration files are embedded in the application.

**Version: 0.0.1, not published.** iOS 15+, Swift 5.9+. iPhone and iPad are the initial supported devices. The macOS package target is for core development/tests; macOS push delivery is not implemented.

## Install

Before publication, add this directory as a local package in Xcode. After a verified `0.0.1` release, add the actual repository URL through **File → Add Package Dependencies** and select the **PushPort** product for the application target.

```swift
import PushPort

// At application launch; choose the environment matching aps-environment in the signed app.
try PushPort.shared.initialize(appId: "YOUR_PUSHPORT_APP_ID", environment: .sandbox)
```

Forward the two native APNs registration callbacks in your app delegate:

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    PushPort.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    PushPort.shared.didFailToRegisterForRemoteNotifications(error: error)
}
```

Enable **Push Notifications** in the application's Signing & Capabilities. For development builds use `.sandbox`; for App Store/TestFlight use `.production`. No automatic permission prompt is displayed at initialization:

```swift
// From a button / deliberate permission flow on the main actor:
let granted = try await PushPort.shared.requestPermission()
try await PushPort.shared.setSubscribed(false)
try await PushPort.shared.setSubscribed(true)
try await PushPort.shared.setLocale("uk-UA")
try await PushPort.shared.setLocale(nil) // Automatic app/system locale again.
PushPort.shared.sync()

PushPort.shared.onStatusChange = { status in
    // status: installationId, subscribed, notificationsEnabled, hasToken, locale, lastSyncedAt, syncError.
}
PushPort.shared.onNotificationOpened = { notification in
    // Handle notification.messageId and optional HTTPS notification.clickURL in your app router.
}
```

All public iOS operations run on the main actor. Initialization and preference updates perform short local file operations. Networking is asynchronous; status reports the last server acknowledgment. The SDK owns one installation per app, and refuses changing its App ID/server/environment. Clearing app data/reinstalling creates a new installation; it does not identify a person or hardware device.

## Images and notification handling

Add a **Notification Service Extension** in Xcode, link the **PushPortNotificationService** product to that extension only, and use the subclass in [Examples/NotificationService](Examples/NotificationService). The server payload needs `aps.mutable-content = 1` and `image_url`. HTTPS JPEG/PNG/GIF images are limited to 5 MiB and a 20-second resource timeout. On download failure or extension expiry, the original text is delivered.

The main SDK installs a forwarding `UNUserNotificationCenterDelegate`, preserving an existing host delegate. Install your own delegate **before** initialization. Alternatively use `manageNotificationDelegate: false` and call `handleNotificationResponse(_:)` from your own delegate. There is no method swizzling. The host controls click navigation. See [lifecycle details](docs/architecture.md).

## Server readiness

This SDK uses the new `/api/v1/sdk/apps/{appId}/platforms/ios` contract. The accompanying local backend changes implement registration/configuration/events, preserve Android compatibility, and report `deliveryReady: false`. The existing production deployment is still Android-only. APNs sender credentials, sender implementation, dashboard credential fields and production rollout are a subsequent integration step; publishing this package alone does not enable server delivery.

SDK-side handling can also be tested on a simulator with `simctl push`; actual APNs delivery needs an Apple Developer account, signed app and server configuration. No server or Firebase app has been registered on your behalf.

## Quality and publication

- [Publish step by step — Russian](docs/publishing.ru.md)
- [Architecture, lifecycle and data](docs/architecture.md)
- [Wire contract](docs/protocol.md)
- [Testing](docs/testing.md)
- [Contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md)

`swift test` runs the portable engine tests. The macOS CI additionally builds and tests the real iOS targets on Simulator. A Linux test pass does **not** validate UIKit, APNs registration, Objective-C selectors or the Notification Service Extension. All iOS gates must pass before the first release.

Apache-2.0 · Copyright 2026 Oleh Yurkov · support@pushport.dev
