#!/bin/bash
# Scripts/create_release.sh — Génère tous les livrables de production (DMG, ZIP, DEB Sileo)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.2.0}"
OUTPUT="$ROOT/releases/v$VERSION"
mkdir -p "$OUTPUT"

echo "==> 1. Compilation du package iPad (Sileo / Cydia)..."
cd "$ROOT/iPad"
export THEOS="${THEOS:-$HOME/theos}"
export PATH="$THEOS/bin:$PATH"
make clean >/dev/null 2>&1
make package FINALPACKAGE=1
cp "$ROOT/iPad/packages/com.displaypad.ipad_${VERSION}_iphoneos-arm.deb" "$OUTPUT/"

echo "==> 2. Compilation de l'application Mac..."
cd "$ROOT"
./Scripts/build_mac_app.sh

APP="$HOME/Applications/DisplayPADMac.app"

echo "==> 3. Création du ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/DisplayPADMac-v$VERSION.zip"

echo "==> 4. Création du DMG macOS..."
TEMP_DMG="/tmp/DisplayPADMac_dmg"
rm -rf "$TEMP_DMG"
mkdir -p "$TEMP_DMG"
ditto "$APP" "$TEMP_DMG/DisplayPADMac.app"
ln -s /Applications "$TEMP_DMG/Applications"
rm -f "$OUTPUT/DisplayPADMac-v$VERSION.dmg"
hdiutil create -volname "DisplayPAD" -srcfolder "$TEMP_DMG" -ov -format UDZO "$OUTPUT/DisplayPADMac-v$VERSION.dmg" >/dev/null
rm -rf "$TEMP_DMG"

echo "==> 5. Génération des checksums SHA256..."
cd "$OUTPUT"
shasum -a 256 "DisplayPADMac-v$VERSION.dmg" "DisplayPADMac-v$VERSION.zip" "com.displaypad.ipad_${VERSION}_iphoneos-arm.deb" > SHA256SUMS.txt

echo "=========================================================="
echo "Release v$VERSION générée avec succès dans :"
echo "$OUTPUT"
echo "=========================================================="
