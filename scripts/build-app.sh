#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

configuration="${CONFIGURATION:-release}"
binary_name="AiQokkaMenubar"
swift build -c "$configuration"
build_bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_bundle="$project_root/dist/aiquokka.app"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp "$build_bin_path/$binary_name" "$app_bundle/Contents/MacOS/$binary_name"
cp "$project_root/Sources/AiQokkaMenubar/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
chmod 755 "$app_bundle/Contents/MacOS/$binary_name"

plutil -replace CFBundleExecutable -string "$binary_name" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundlePackageType -string "APPL" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleVersion -string "1" "$app_bundle/Contents/Info.plist"

signing_identity="${SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi

if [[ -n "$signing_identity" ]]; then
    codesign --force --deep --timestamp=none --sign "$signing_identity" "$app_bundle"
    echo "Built and signed $app_bundle ($signing_identity)"
else
    codesign --force --deep --timestamp=none --sign - "$app_bundle"
    echo "Built $app_bundle (ad-hoc signature; notifications may require a locally signed build)"
fi
