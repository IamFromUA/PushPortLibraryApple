# Contributing

Read README and docs before changing the API. Keep public operations small and document behavior, errors, threading, persistence and platform limits. Prefer a focused adapter/transport/storage boundary to duplicate implementations.

Run the repository's documented checks and add behavioral regression coverage for changed persistence, authentication, retry, permissions and notification handling. Test a packaged dependency in an independent consumer before release. Native iOS and KMP/Swift linking changes require macOS/Xcode verification.

Use synthetic test identities and endpoints. Never include real push tokens, customer credentials or personal data in examples/tests. Preserve Apache-2.0 notices. A release tag is immutable; follow Semantic Versioning and document user-visible changes in CHANGELOG.md.
