# ``PushPort``

Connect an iOS application to PushPort with its App ID. The native SDK registers APNs tokens, synchronizes subscription and locale information, and records notification interactions.

## Integration

Initialize at application launch, forward the APNs registration callbacks and request notification permission from a deliberate user action. The host owns Apple signing/capabilities and click navigation.

## Persistence

Each installation has a durable random identifier and bearer secret. Preferences are independent of system permission. Network failures retain pending state and retry when the application can run.

See the repository README and publishing guide for complete examples, limitations and server readiness.
