# PushPort Apple SDK

[![Native iOS verification](https://github.com/IamFromUA/PushPortLibraryApple/actions/workflows/verify.yml/badge.svg)](https://github.com/IamFromUA/PushPortLibraryApple/actions/workflows/verify.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

Native Swift SDK for iOS push subscriptions, device metadata and notification interactions. Distributed as a normal Swift package. No Firebase dependency, account credentials or Google configuration files are embedded in the application.

**Version: 0.1.1.** iOS 15+, Swift 5.9+. iPhone and iPad are the initial supported devices. The macOS package target is for core development/tests; macOS push delivery is not implemented. Read [server readiness](#server-readiness) and the diagnostics guide before planning production delivery.

## Install

In Xcode, open **File → Add Package Dependencies**, paste the repository URL below, choose **Exact Version: 0.1.1**, and add the **PushPort** product to your application target:

```text
https://github.com/IamFromUA/PushPortLibraryApple.git
```

For a Swift package consumer, add this dependency to `Package.swift` and `.product(name: "PushPort", package: "PushPortLibraryApple")` to your iOS target:

```swift
.package(url: "https://github.com/IamFromUA/PushPortLibraryApple.git", exact: "0.1.1")
```

No App Store submission, CocoaPods account or private package registry is required. See the [Russian integration guide](docs/getting-started.ru.md) for the full setup.

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
    // Custom routing, including in the older 0.0.2 SDK.
    guard let url = notification.clickURL else { return }
    UIApplication.shared.open(url)
}
```

All public iOS operations run on the main actor. Initialization and preference updates perform short local file operations. Networking is asynchronous; status reports the last server acknowledgment. The SDK owns one installation per app, and refuses changing its App ID/server/environment. Clearing app data/reinstalling creates a new installation; it does not identify a person or hardware device.

## Application profiles

Available in Apple SDK 0.1.1.

All accounts have access to app profiles by default. An operator can change access under **Users**. Profiles start off for each project. The owner or a manager can enable **App profiles** at project creation or in Settings. Each project has up to three named profiles including `default`. IDs survive renames. The optional `value` is public and can identify a screen or a content variant.

```swift
let profile = await PushPort.shared.resolveAppProfile() // after initialize, on the main actor
if profile.value == "catalog" { openCatalog() } else { openHome() }
```

`PushPort.shared.appProfile` reads the current local profile immediately.

The startup check shares the normal configuration request. When the network is slow, the resolver waits up to about one second and uses the last confirmed profile, or `default` on the first offline launch. Turning either switch off selects the default on the next successful check. The app chooses its own screen and can ignore unknown values. Reading the profile needs no notification permission.

## Images and notification handling

Add a **Notification Service Extension** in Xcode, link the **PushPortNotificationService** product to that extension only, and use the subclass in [Examples/NotificationService](Examples/NotificationService). The server payload needs `aps.mutable-content = 1` and `image_url`. Version 0.0.2 supports HTTPS JPEG/PNG/GIF and WebP-to-PNG where decoding is available, with bounded 2000-pixel sampling and a 10-second resource timeout. Downloads default to 5 MiB, respect the project setting of 1–20 MiB and are capped at the iOS attachment ceiling of 10 MiB. The app icon remains bundled in the host app. On download failure or extension expiry, the original text is delivered.

For background diagnostics and consent-controlled image downloads, enable the same App Group entitlement in the app and extension and set the same `PushPortAppGroup` string in both Info.plist files. Events upload on the host app's next sync. In the 0.1.1 SDK, an extension configured with a group returns the original text while consent is pending, revoked or unreadable. The host writes the decision at startup and when consent changes. Standalone extensions can display images without a group and cannot read the host's consent. See [diagnostics](docs/diagnostics.md).

The main SDK installs a forwarding `UNUserNotificationCenterDelegate`, preserving an existing host delegate. Install your own delegate **before** initialization. Alternatively use `manageNotificationDelegate: false` and call `handleNotificationResponse(_:)` from your own delegate. There is no method swizzling. In earlier 0.0.2 builds the host controls navigation. A manually forwarding host can opt in with `handleNotificationResponse(_:openDefaultLink: true)`. The 0.1.1 SDK opens a public HTTPS destination on a default tap when the host has no handler. It records `clicked` for the interaction and `link_opened` or `link_failed` for the system navigation result. This result measures handoff to iOS. A custom router can use `reportLinkResult(for:opened:)` with its actual result. See [lifecycle details](docs/architecture.md).

For a custom router using the 0.1.1 SDK:

```swift
PushPort.shared.onNotificationOpened = { notification in
    guard let url = notification.clickURL else { return }
    UIApplication.shared.open(url, options: [:]) { accepted in
        PushPort.shared.reportLinkResult(for: notification, opened: accepted)
    }
}
```

## Server readiness

This SDK uses `/api/v1/sdk/apps/{appId}/platforms/ios`. In PushPort, enable iOS for your application, save the exact Bundle ID, then open Settings → Apple APNs. Upload the `.p8` key with Team ID and Key ID for each required environment (Sandbox or Production). The server uses APNs directly; Firebase is unnecessary. Saved credentials enable routing but do not prove delivery: verify a signed application on a real device before launching a campaign. See the [complete setup guide](https://pushport.dev/docs/#apns).

SDK-side handling can also be tested on a simulator with `simctl push`; actual APNs delivery needs an Apple Developer account, signed app and server configuration. The SDK never creates Apple identifiers or uploads provider credentials from a client application.

## Quality and publication

- [Publish step by step — Russian](docs/publishing.ru.md)
- [Architecture, lifecycle and data](docs/architecture.md)
- [Wire contract](docs/protocol.md)
- [Testing](docs/testing.md)
- [Contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md)

`swift test` runs the portable engine tests. The macOS CI additionally builds and tests the iOS targets on Simulator, verifies Objective-C bridge selectors and builds an independent app plus extension using the public Git package. See [verification evidence and limits](docs/verification.md). A native build does not verify actual APNs delivery.

Apache-2.0 · Copyright 2026 Oleh Yurkov · support@pushport.dev

See [diagnostics, consent, images and user profiles](docs/diagnostics.md) for version 0.1.1.
