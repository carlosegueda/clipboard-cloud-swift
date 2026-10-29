#!/usr/bin/env bash
# Compila en release y empaqueta como ClipboardCloud.app (LSUIElement = solo menubar).
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="ClipboardCloud"
APP_DIR="build/${APP_NAME}.app"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
mkdir -p "$APP_DIR/Contents/Resources"
cp Sources/ClipboardCloud/Resources/Oswald.ttf Sources/ClipboardCloud/Resources/Oswald-OFL.txt "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>biz.authcode.ClipboardCloud</string>
    <key>CFBundleName</key>
    <string>Clipboard Cloud</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Clipboard Cloud sube a tu historial las capturas de pantalla que macOS guarda en el Escritorio.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Clipboard Cloud sube a tu historial las capturas de pantalla guardadas en esta carpeta.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Clipboard Cloud sube a tu historial las capturas de pantalla guardadas en esta carpeta.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" >/dev/null
echo "Listo: $APP_DIR"
