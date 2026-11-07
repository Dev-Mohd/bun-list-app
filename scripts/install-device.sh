#!/usr/bin/env bash
# Builds BunnList and installs it on the iPhone connected to this Mac (USB, or Wi-Fi once paired in Xcode).
# Usage: ./scripts/install-device.sh [branch]      (default: the branch you're on)
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
echo "▸ Updating to $branch"
git fetch origin "$branch"
git checkout "$branch"
git pull --ff-only origin "$branch"

echo "▸ Generating the Xcode project"
if command -v mint >/dev/null 2>&1; then
  mint run yonaskolb/XcodeGen@2.42.0 xcodegen generate
elif command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
else
  echo "XcodeGen is missing. Install it once with:  brew install xcodegen" >&2
  exit 1
fi

echo "▸ Looking for your iPhone"
devices_json="$(mktemp)"
xcrun devicectl list devices --json-output "$devices_json" >/dev/null
udid="$(/usr/bin/python3 - "$devices_json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and conn.get("pairingState") == "paired" and conn.get("tunnelState") != "unavailable":
        print(hw.get("udid", "")); break
PY
)"
rm -f "$devices_json"
if [[ -z "$udid" ]]; then
  echo "No iPhone found. Connect it with a cable, unlock it, tap «Trust», and make sure Developer Mode is on" >&2
  echo "(Settings › Privacy & Security › Developer Mode)." >&2
  exit 1
fi
echo "  found $udid"

echo "▸ Building (the first build takes a few minutes)"
xcodebuild -project BunnList.xcodeproj -scheme BunnList -configuration Debug \
  -destination "id=$udid" -derivedDataPath build/DerivedData -allowProvisioningUpdates \
  -quiet build

app="build/DerivedData/Build/Products/Debug-iphoneos/BunnList.app"
echo "▸ Installing on the iPhone"
xcrun devicectl device install app --device "$udid" "$app"
echo "▸ Opening BunnList"
xcrun devicectl device process launch --device "$udid" dev.devmohd.bunnlist >/dev/null || true
echo "✓ Done"
