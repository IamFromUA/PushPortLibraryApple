# ``PushPortNotificationService``

Attach an image to a PushPort notification through an iOS Notification Service Extension.

## Add the extension

Create a Notification Service Extension target in Xcode and link the `PushPortNotificationService` package product to it. Subclass the service in the extension's own module:

```swift
import PushPortNotificationService

final class NotificationService: PushPortNotificationService {}
```

Keep `NSExtensionPrincipalClass` set to `$(PRODUCT_MODULE_NAME).NotificationService`. The host app uses the separate `PushPort` product.

## Payload and fallback

An image notification contains `aps.mutable-content = 1`, `pushport_app_id` and `image_url`. The image must use public HTTPS and a supported JPEG, PNG or GIF MIME type. SDK 0.0.2 can also convert WebP to PNG when platform decoding supports it. Downloads default to 5 MiB, honor the project's 1–20 MiB setting and are capped at the iOS attachment ceiling of 10 MiB. Decoding is bounded, pictures sample to 2000 pixels per side and the resource timeout is 10 seconds. Invalid URLs, failed or oversized downloads, and extension expiration preserve the original notification text.

For consent-controlled downloads or background diagnostics, add the same App Group entitlement and `PushPortAppGroup` Info.plist string to both targets. The host writes its consent decision to the group and uploads the extension’s queued events at the next sync. In the development SDK, a configured extension delivers the original text if the decision is missing, unreadable or denied for this app. Without a group, the extension can fetch images independently. The app records foreground presentation separately from background attachment preparation. See `docs/diagnostics.md` in the repository.
