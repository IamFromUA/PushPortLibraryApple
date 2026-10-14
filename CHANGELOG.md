# Changelog

## 0.0.2 — 2026-10-14

- Durable batched notification diagnostics with stable event IDs, bounded outbox and retry acknowledgement.
- Consent gating, foreground sessions/usage, direct and estimated influenced returns.
- Confirmed user profiles, verified External ID login/logout, tags, explicit contact/location data and custom events.
- Automatic project image limits (5 MiB by default); safe text fallback when image processing fails.
- Backward-compatible installation identity and native SDK/bridge methods.
- Notification Service Extension image diagnostics through an optional shared App Group; JPEG/PNG/GIF and WebP-to-PNG, 2000-pixel sampling. iOS app icons remain bundled; OS attachment ceiling is 10 MiB.


## 0.0.1 — 2026-09-13

- Swift package and native iOS integration; portable engine tests and macOS Simulator CI.
- Immutable application binding, independent permission/subscription state and locale synchronization.
- Documentation, examples, Apache-2.0 notices, verification workflow and publication guide.
- Optional Notification Service Extension for HTTPS images with size and time limits.
- Native Objective-C bridge surface for the separately distributed KMP adapter.
- Public Swift Package Manager distribution and an independent app/extension consumer check.

Initial SDK release. APNs server delivery and real-device end-to-end validation are a separate integration stage; see [server readiness](README.md#server-readiness).
