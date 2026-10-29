#!/usr/bin/env bash
# Compila el proyecto de Xcode en release y deja la app en build/ClipboardCloud.app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="ClipboardCloud"

xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath build/dd build -quiet

rm -rf "build/${APP_NAME}.app"
cp -R "build/dd/Build/Products/Release/${APP_NAME}.app" build/
echo "Listo: build/${APP_NAME}.app"
