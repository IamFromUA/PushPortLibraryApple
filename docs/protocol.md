# PushPort SDK platform protocol 1 (draft release 0.0.1)

Android's existing `/api/v1/sdk/apps/{appId}` v1 API is preserved. Native Apple and Web use a separate platform boundary under `/api/v1/sdk/apps/{appId}/platforms/{ios|web}`. New backend source is prepared locally; it is not deployed by this SDK task.

| Request | Purpose |
| --- | --- |
| `GET .../ios/config?bundleId=...` | Check enabled iOS platform and exact registered Bundle ID |
| `GET .../web/config?origin=...` | Check enabled website/exact Origin and obtain public VAPID key |
| `PUT .../{platform}/installations/{installationId}` | Register/update a platform snapshot |
| `POST .../{platform}/installations/{installationId}/events` | Idempotent opened event |

Config response: `appId`, `platform` (`IOS`/`WEB`), `protocolVersion: 1`, `deliveryReady: false`, optional `vapidPublicKey`. Registration support does not imply a commissioned provider sender. The current sender/campaign dispatcher remains Android/FCM only; APNs/Web credentials/sender/UI and deployment are a separate step. Other SDK targets cannot enter Android sending queues.

Configuration binds the installation to one app, backend and application identifier. A canonical random UUID identifies the installation. A CSPRNG-generated 32-byte secret, base64url without padding (43 characters), authorizes PUT/events through `Authorization: Bearer ...`. The backend stores a hash. Never place credentials in URLs, SDK source or public config. APNs `.p8` keys and Web VAPID private keys belong exclusively to the server.

Both snapshots carry `revision` (monotonically increasing integer >= 1), `platform`, `applicationIdentifier`, `language`, `locale`, `appLocales`, `systemLocales`, `timezone`, `notificationsEnabled`, `pushSubscribed`, `sdkVersion`, `appVersion`, `osVersion`, `model`.

Apple adds `pushToken` (lowercase hex or null) and `apnsEnvironment` (`sandbox`/`production`). `applicationIdentifier` is the Bundle ID. A pending permission/token still registers the installation. APNs token length is not assumed to be a fixed number of bytes. No FCM/Android identifier is synthesized.

Web adds `webSubscription` (null or `{endpoint, expirationTime, keys: {p256dh, auth}}`). Keys use unpadded base64url. The endpoint is HTTPS. `applicationIdentifier` is the exact scheme/host/port origin. The browser Origin header must match the registered origin for PUT/events and any cross-origin GET; CORS permits only it, never cookies. Public config GET also accepts a missing Origin because same-origin browser GET requests may omit it; the query origin is still validated against the app. Server-side provider delivery must validate outbound destinations/DNS/IPs against SSRF before contacting subscription endpoints.

Owner provisioning for pre-release Web tests: authenticated `POST /api/v1/apps/{appId}/platforms/web/configure` creates one stable P-256 keypair and returns only `vapidPublicKey`. Private material is encrypted with the backend master key. Repeated calls preserve existing subscriptions' key. This does not activate a sender. A browser-session route is also provided; its normal CSRF/session requirements apply.

Registration responds `{installationId, syncedAt}`; an older revision cannot replace newer state. A 409 on a first-registration race can be retried with the same identity. Token changes preserve the user's subscription choice. Existing Android fields/table records are migrated additively (V8), not deleted or rewritten to fictitious platforms.

Opened event body: `{messageId: "canonical-uuid", type: "opened"}`. SDKs use bounded durable outboxes and server idempotency, not a retry-generated message ID. A 204 acknowledges the event; permission/last-seen is not a delivery receipt.

APNs display payload: `aps.alert.title/body`, optionally `aps.sound`, `aps.mutable-content:1`; top-level `pushport_app_id`, `pushport_message_id`, `image_url`, `click_url`. Web Push plaintext payload uses the same top-level identifiers and `title`, `body`, `image_url`, `click_url`. The Web sender must encrypt this payload according to Web Push standards before transmission. The shared API never assumes Apple/browser identifiers can be Android IDs.

HTTP 400: invalid payload; 401: installation credential; 403: identifier/origin mismatch; 404: application/route absent; 409: configuration conflict; 429/5xx/network: bounded retry. SDK diagnostics omit raw response bodies, tokens, endpoints and bearer secrets.
