#!/bin/bash
# Builds FocusBanner.app from banner.swift.
set -euo pipefail
cd "$(dirname "$0")"

APP="FocusBanner.app"
VERSION="1.0.0"

echo "Compiling…"
swiftc -O -o focusbanner banner.swift

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp focusbanner "$APP/Contents/MacOS/focusbanner"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>FocusBanner</string>
    <key>CFBundleDisplayName</key>     <string>Focus Banner</string>
    <key>CFBundleIdentifier</key>      <string>com.guillaumepauli.focusbanner</string>
    <key>CFBundleExecutable</key>      <string>focusbanner</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP (ad-hoc signed)"
