# Architecture and lifecycle

| Module | Responsibility |
| --- | --- |
| PushPortCore | Immutable configuration, durable installation/snapshot/event state, HTTP transport, serial actor engine |
| PushPort | iOS metadata, APNs callbacks, permissions, foreground/connectivity observation, public Swift API and KMP bridge |
| PushPortNotificationService | Independent extension-safe HTTPS image downloader; no UIApplication or registration engine |

The actor commits a revision before sending it. Concurrent captures are coalesced; a newer revision that arrives during an HTTP request is sent afterward. Registration uses PUT, and the server ignores older revisions. Each installation owns a cryptographically random 32-byte bearer secret. Configuration and identity persist in an atomic, app-container file excluded from backup and protected until first unlock on iOS. Corrupt/unreadable state fails explicitly instead of silently creating duplicate installations. App ID, server, bundle ID and APNs environment cannot change for an existing installation.

Opened events are app-scoped, deduplicated in a bounded durable outbox (100 events), and removed after acknowledgment. The server must implement opened-event idempotency. HTTP failures do not include response bodies or credentials in diagnostics. Redirects, cookies, shared URL caches and credential stores are disabled on the SDK API transport.

Permission and the app's subscription preference are independent. An opt-out is persisted even if the phone is offline. Foreground presentation is suppressed after the local opt-out is observed. Background alerts already accepted by APNs can still appear; only the backend can stop future sends after it receives the preference. The SDK does not call global unregister/remove-all APIs that could interfere with another push provider.

App/system locale, timezone, permission, APNs token, app/OS version and generic device model are synchronized on launch, foreground, locale/timezone changes, token callbacks and network restoration. No advertising ID, IDFV, contacts, GPS, email, device name or hardware serial is collected. Server IP-derived country is distinct from language/locale. The host must disclose actual collection and any additional association it introduces. Privacy manifests are included in the main product and extension product.

Retry uses capped exponential delay with jitter while the process can run. iOS may suspend/terminate an app; there is no promise of a permanent background service. Persisted changes resume on the next launch/foreground or network event. Permission prompting is deliberate and separate from initialization.

The KMP bridge is an explicit small Objective-C surface. It forwards to the same Swift singleton. It has no network stack or second installation. Keep its selectors synchronized with the header published in the KMP repository, and test both packages on macOS before changing it.

Current limitations: iOS/iPadOS only, no silent-push background execution, no mutable APNs environment after binding, no arbitrary URL scheme navigation, no delivery receipt inferred from a token. Provider configuration belongs in the PushPort application settings, separately from SDK installation. Validate actual delivery before campaigns.
