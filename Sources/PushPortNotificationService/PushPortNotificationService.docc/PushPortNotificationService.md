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

An image notification contains `aps.mutable-content = 1`, `pushport_app_id` and `image_url`. The image must use public HTTPS and a supported JPEG, PNG or GIF MIME type. SDK 0.0.2 can also convert WebP to PNG when platform decoding supports it. Downloads default to 5 MiB, honor the project's 1–20 MiB setting and are capped at the iOS attachment ceiling of 10 MiB. Decoding is bounded, pictures sample to 2000 pixels per side and the resource timeout is 20 seconds. Invalid URLs, failed or oversized downloads, and extension expiration preserve the original notification text.

The extension does not register an installation, request permissions or contain APNs provider credentials. No App Group is required for image handling. For background receipt/image diagnostics, add the same App Group entitlement and `PushPortAppGroup` Info.plist string to both targets. The extension shares only bounded diagnostic event files; the host uploads them on its next sync. Preparing an attachment does not prove iOS displayed the notification. See `docs/diagnostics.md` in the repository.
