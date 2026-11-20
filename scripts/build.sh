#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
BIN_DIR=$(swift build -c release --show-bin-path)
OUTPUT_DIR="$PWD/build"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/viewfit-build.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/ViewFit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ChromeExtension"
cp "$BIN_DIR/ViewFit" "$APP/Contents/MacOS/ViewFit"
cp "$BIN_DIR/ViewFitBridge" "$APP/Contents/MacOS/ViewFitBridge"
for file in ChromeExtension/*; do
    if [ -f "$file" ]; then cp "$file" "$APP/Contents/Resources/ChromeExtension/"; fi
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ViewFit · 随屏</string>
<key>CFBundleDisplayName</key><string>ViewFit · 随屏</string>
<key>CFBundleIdentifier</key><string>com.avenry.screenscale</string>
<key>CFBundleExecutable</key><string>ViewFit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>根据显示器连接状态，操作 Codex 和微信的缩放菜单。</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/ViewFitBridge"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Build outside synced Documents: Finder/FileProvider may reattach FinderInfo
# between attribute cleanup and signing. The ZIP preserves the verified bundle.
mkdir -p "$OUTPUT_DIR"
ditto --norsrc "$APP" "$OUTPUT_DIR/ViewFit.app"
ditto -c -k --norsrc --keepParent "$APP" "$OUTPUT_DIR/ViewFit.zip"
printf '%s\n' "$OUTPUT_DIR/ViewFit.app" "$OUTPUT_DIR/ViewFit.zip"
