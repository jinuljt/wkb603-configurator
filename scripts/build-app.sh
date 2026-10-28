#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for architecture in arm64 x86_64; do
  swift build -c release --arch "$architecture"
done
output_root="${1:-dist}"
app="$output_root/WKB603 Configurator.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
arm_bin="$(swift build -c release --arch arm64 --show-bin-path)/WKB603Configurator"
intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)/WKB603Configurator"
lipo -create "$arm_bin" "$intel_bin" -output "$app/Contents/MacOS/WKB603Configurator"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier org.jinuljt.WKB603Configurator "$app"
"$app/Contents/MacOS/WKB603Configurator" --self-test
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_root/WKB603-Configurator-macOS-universal.zip"
(cd "$output_root" && shasum -a 256 WKB603-Configurator-macOS-universal.zip > SHA256SUMS.txt)
printf 'Built universal app: %s\n' "$app"
