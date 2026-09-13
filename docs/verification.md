# Verification — 2026-09-13

Native verification runs on GitHub-hosted macOS with Xcode. The [verification workflow](https://github.com/IamFromUA/PushPortLibraryApple/actions/workflows/verify.yml) records the exact commit, toolchain, test results and consumer build for each push/tag.

The [first successful native run](https://github.com/IamFromUA/PushPortLibraryApple/actions/runs/34770319836) verified:

- Six portable engine tests on macOS: identity/persistence, invalid configuration/storage, locale, token refresh with opt-out, concurrent revisions and event retry.
- Eight iOS Simulator tests: the six engine cases plus notification parsing/safe URLs and all Objective-C bridge selectors.
- Notification Service Extension build with extension-only APIs enabled.
- An independent app and extension resolving the public Git package by commit and linking both products. The app references the native KMP bridge; both privacy manifests are included in the output.

CI also builds DocC documentation. Tag runs resolve the independent consumer by exact release version. Downloadable test results and documentation archives are attached to each successful workflow run.

Earlier portable checks also passed with Swift 6.2 on Linux. Those checks do not replace the native iOS checks above.

Not validated by this SDK release: real APNs delivery, notification extension behavior on a physical device, Apple signing/provisioning, production server rollout, or final Kotlin/Native + Swift linkage of the separate KMP package. The consumer checks compilation and native linkage; it does not initialize an installation, send notifications or request permission. See [testing.md](testing.md) for the subsequent device/provider scenarios.
