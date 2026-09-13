#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${PUSHPORT_RELEASE_VERSION:-}" ]]; then
  python3 scripts/create-consumer.py --output .build/consumer --version "$PUSHPORT_RELEASE_VERSION"
else
  python3 scripts/create-consumer.py --output .build/consumer --revision "${GITHUB_SHA:-$(git rev-parse HEAD)}"
fi
plutil -lint .build/consumer/Consumer.xcodeproj/project.pbxproj
xcodebuild -project .build/consumer/Consumer.xcodeproj -scheme Consumer \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/consumer-derived \
  build CODE_SIGNING_ALLOWED=NO
app=.build/consumer-derived/Build/Products/Debug-iphonesimulator/Consumer.app
test -d "$app/PlugIns/NotificationService.appex"
test "$(find "$app" -name PrivacyInfo.xcprivacy | wc -l | tr -d ' ')" -ge 2
echo 'Independent app and extension linked successfully with privacy manifests.'
