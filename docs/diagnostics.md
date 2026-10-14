# Diagnostics and user data — 0.0.2

Initialize normally. SDK-owned notifications automatically record receipt, presentation API results, image preparation/failures and clicks when the platform exposes them. A provider acceptance is not device delivery; an accepted notification API call is not a human view. No notification text, image URL, raw exception, credential or token is placed in diagnostics. Sessions are foreground visits separated by at least 30 seconds in the background; foreground duration uses a monotonic clock. A session within 60 seconds of a click is direct; one within 1 hour of a receipt without a click is estimated influenced. Registration/deposit/redeposit still come from the partner.

Diagnostics persist across restarts. The outbox holds 1000 events and uploads batches of 100 using stable event IDs and accepted-ID acknowledgement. Excess events are dropped and counted. Missing server capabilities or HTTP 404/405 disable uploads until a later configuration refresh. Old installations and legacy opened events continue working. Consent blocks collection, permission prompts and PushPort networking; revocation clears pending telemetry and user mutations, without deleting server history.

Images default to 5 MiB and use the project's 1–20 MiB setting automatically. iOS caps downloads at its 10 MiB attachment ceiling. Downloads are time/byte bounded; failures retain text. Images use public HTTPS without credentials or redirects. Web downloads need image-host CORS permission. PNG/JPEG/GIF are portable; WebP is converted by iOS where supported. Pictures sample to 2000 px, Web icons to 256 px when browser image decoding and canvas are available. iOS notification icons come from the installed app; Android small_icon names are not Web badge URLs.

User profiles expose the confirmed userId. setTags supports arbitrary string values and null deletion (50 keys, 64/256 characters). login requires an External ID and a short-lived identity proof issued by the customer's trusted backend; no master key in an SDK. logout detaches this installation. setEmail, setPhoneNumber, setLocation and trackEvent collect only explicitly supplied values, without requesting contacts or GPS. The user outbox holds 100 operations, persists monotonic revisions and discards old unsent changes on account switches.

## Apple

For background receipt and image diagnostics, install PushPortNotificationService in the existing Notification Service Extension. Enable the same App Group entitlement in the app and extension and put the same string in both Info.plist files:

```xml
<key>PushPortAppGroup</key>
<string>group.com.example.app.pushport</string>
```

The extension stores only bounded event files in that group, not installation credentials. The host imports and uploads them on its next foreground/connectivity sync. Without the group, foreground notification and click/session metrics still work; background receipt/image metrics are unavailable. The extension preparing content does not prove iOS presented it. Existing APNs callbacks and explicit notification permission remain required. Interrupted/force-quit processes can delay reports.

```swift
try await PushPort.shared.setConsentRequired(true) // before initialize, if needed
try PushPort.shared.initialize(appId: "YOUR_APP_ID")
try await PushPort.shared.setConsentGiven(true)
try await PushPort.shared.setTags(["buyer": "team1", "removed": nil])
let userId = PushPort.shared.user?.userId
```

## Web

Update both the page package and the copied same-origin pushport-sw.js. Browsers control whether image/icon options are displayed; downloaded/attached means SDK preparation/API acceptance, not a screenshot verification. The original text appears first; an image replacement is silent and skipped if the notification is no longer active. Visibility changes collect sessions; browser shutdown can lose the uncheckpointed tail.

```ts
const client = await PushPort.initialize({ appId: "YOUR_APP_ID", consentRequired: true });
await client.setConsentGiven(true);
await client.setTags({ buyer: "team1", removed: null });
const userId = client.user()?.userId;
```

## KMP

Use dev.pushport:kmp-sdk:0.0.2. Android's transitive SDK is 0.0.5. Link the Apple Swift package 0.0.2 in the iOS host, or install @pushport/web-sdk 0.0.2 in a Kotlin/JS host. Configure native permissions/extension/worker once. KMP forwards user/consent APIs; the native SDK automatically collects notification metrics and sessions. JVM has no native delivery driver.
