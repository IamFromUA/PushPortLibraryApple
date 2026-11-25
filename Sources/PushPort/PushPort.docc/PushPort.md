# ``PushPort``

Connect an iOS application to PushPort with its App ID. The native SDK registers APNs tokens, synchronizes subscription and locale information, and records notification interactions.

## Integration

Initialize at application launch, forward the APNs registration callbacks and request notification permission from a deliberate user action. Configure signing and capabilities in the host app. Default taps open public HTTPS links. Hosts that implement custom routing can report the actual navigation result with `reportLinkResult(for:opened:)`.

## Persistence

Each installation has a durable random identifier and bearer secret. Preferences are independent of system permission. Network failures retain pending state and retry when the application can run.

See the repository README and publishing guide for complete examples, limitations and server readiness.
