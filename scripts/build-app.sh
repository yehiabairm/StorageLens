#!/bin/zsh
# Builds build/StorageLens.app (release, ad-hoc signed).
# Usage: zsh scripts/build-app.sh [--install]   (--install copies it to ~/Applications)
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
APP=build/StorageLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/StorageLens "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature. Full Disk Access is tied to it, so a rebuild may need a new grant.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/StorageLens.app
  cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/StorageLens.app"
fi
