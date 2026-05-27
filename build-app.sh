#!/bin/bash
# Build Meister Proper.app bundle from SwiftPM executable.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Meister Proper"
BUNDLE_ID="com.meisterproper.app"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH=".build/${CONFIG}/MeisterProper"
[ -x "$BIN_PATH" ] || { echo "Binary not found at $BIN_PATH"; exit 1; }

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/MeisterProper"
chmod +x "${APP_DIR}/Contents/MacOS/MeisterProper"

# Embed app icon if present (regenerate .icns from PNG when newer)
ICON_SRC="Resources/AppIcon.png"
ICON_ICNS="Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
  if [ ! -f "$ICON_ICNS" ] || [ "$ICON_SRC" -nt "$ICON_ICNS" ]; then
    echo "==> Regenerating AppIcon.icns from $ICON_SRC"
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for sz in 16 32 64 128 256 512 1024; do
      sips -z $sz $sz "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null 2>&1
    done
    cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
    cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
    cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
    cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
    cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
    rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
    iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
  fi
  cp "$ICON_ICNS" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>         <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>             <string>1</string>
  <key>CFBundleShortVersionString</key>  <string>1.0.0</string>
  <key>CFBundleExecutable</key>          <string>MeisterProper</string>
  <key>CFBundleIconFile</key>            <string>AppIcon</string>
  <key>CFBundleIconName</key>            <string>AppIcon</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>LSMinimumSystemVersion</key>      <string>14.0</string>
  <key>NSHighResolutionCapable</key>     <true/>
  <key>NSPrincipalClass</key>            <string>NSApplication</string>
  <key>LSApplicationCategoryType</key>   <string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key>    <string>© 2026</string>
  <key>NSAppleEventsUsageDescription</key>
    <string>Meister Proper uses Finder to empty Trash and System Events to manage LaunchAgents.</string>
  <key>NSSystemAdministrationUsageDescription</key>
    <string>Meister Proper requests admin to clean system caches and remove protected items.</string>
  <key>NSDesktopFolderUsageDescription</key>
    <string>Find leftover installer files on your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key>
    <string>Find leftover installer files in Documents.</string>
  <key>NSDownloadsFolderUsageDescription</key>
    <string>Find leftover installer files in Downloads.</string>
</dict>
</plist>
EOF

# ad-hoc sign so Gatekeeper allows local launch
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "==> Built: ${APP_DIR}"
echo "Run with: open \"${APP_DIR}\""
