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

An image notification contains `aps.mutable-content = 1`, `pushport_app_id` and `image_url`. The image must use HTTPS and a supported JPEG, PNG or GIF MIME type. Downloads are limited to 5 MiB and a 20-second resource timeout. Invalid URLs, failed or oversized downloads, and extension expiration preserve the original notification text.

The extension does not register an installation, request permissions or contain APNs provider credentials. No App Group is required for image handling.
