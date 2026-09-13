#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --jobs 2
mkdir -p .build
xcodebuild -list -json > .build/xcode-schemes.json
cat .build/xcode-schemes.json
scheme=$(python3 -c 'import json; d=json.load(open(".build/xcode-schemes.json")); s=d.get("workspace", d.get("project", {}))["schemes"]; print("PushPort-Package" if "PushPort-Package" in s else "PushPort")')
device=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for values in d["devices"].values() for x in values if x.get("isAvailable") and "iPhone" in x["name"]))')
xcodebuild -scheme "$scheme" -destination "platform=iOS Simulator,id=$device" -derivedDataPath .build/ios test CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme PushPortNotificationService -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/extension build APPLICATION_EXTENSION_API_ONLY=YES CODE_SIGNING_ALLOWED=NO
