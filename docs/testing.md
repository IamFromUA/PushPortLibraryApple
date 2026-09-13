# Verification

Portable tests: `swift test --jobs 2`. Covers identity persistence, incompatible binding, corrupted storage, offline retry, opt-out across token refresh, revision concurrency, scoped opened events and locale/config validation.

iOS tests and builds: `bash scripts/verify-ios.sh` on macOS with Xcode + an available iPhone Simulator. This validates code guarded by `#if os(iOS)`, Objective-C bridge selectors, and the extension target. CI runs the same script. Never equate Linux tests to an iOS build.

Manual device checks for release:

1. Fresh installation → initialize → deliberate permission request. Allow and deny in separate fresh runs.
2. Verify installation ID, locale, timezone and permission on the backend; raw APNs tokens stay out of logs.
3. Change app/system language, return from Settings after permission changes, and verify a newer revision.
4. Opt out while offline, restart, reconnect; preference remains off and synchronizes.
5. Deliver text and image payloads. Test bad/oversized image URL and extension timeout: text still displays.
6. Open a notification with the app foreground, background and terminated. Confirm one server-side opened state. Host delegate receives its own notifications and completion callbacks.
7. Reinstall: fresh installation ID. Old token is handled by the backend APNs invalidation policy.
8. Verify development APNs and production/TestFlight separately against the matching credentials/environment.
9. Add the released package by URL/version to an independent app, not only by local path.

No real APNs delivery has been performed in the Windows preparation task. Test payloads are synthetic.
