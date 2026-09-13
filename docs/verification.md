# Preparation checks — 2026-09-13

Passed: Swift 6.2 Linux build and 6 portable engine tests in an isolated container. Identity/persistence, bad storage/configuration, locale, token refresh with opt-out, concurrent revisions and event retry were checked. Privacy plist resources and the SPM manifest are present.

Not run here: iOS Simulator build/tests, Notification Service Extension execution, final KMP/Swift link and real APNs delivery. They require macOS/Xcode and, for real delivery, a configured provider/signed application. The checked-in macOS verification workflow is the next release gate.

The repository has no commit, remote, release tag or public package yet. Do not describe this preparation as a verified production iOS release.
