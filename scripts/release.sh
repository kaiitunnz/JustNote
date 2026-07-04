#!/bin/sh
# Build a signed Release and install it to /Applications. See RELEASE.md.
set -eu
cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/JustNote.app"
DEST="/Applications/JustNote.app"

xcodegen generate
xcodebuild -project JustNote.xcodeproj -scheme JustNote \
  -configuration Release -allowProvisioningUpdates -derivedDataPath build build

osascript -e 'quit app "JustNote"' 2>/dev/null || true
pkill -x JustNote 2>/dev/null || true

rm -rf "$DEST.tmp"
cp -R "$APP" "$DEST.tmp"
codesign --verify --strict "$DEST.tmp"
rm -rf "$DEST"
mv "$DEST.tmp" "$DEST"
echo "Signed & installed: $DEST"
