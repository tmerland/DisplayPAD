#!/bin/bash
# Compile DisplayPADMac et assemble un vrai bundle .app (signature ad hoc).
# Le build se fait hors du dossier synchronisé (OneDrive perturbe .build/).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$HOME/.displaypad-build"
APP="$HOME/Applications/DisplayPADMac.app"

cd "$ROOT/Mac"
swift build --scratch-path "$SCRATCH"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$SCRATCH/debug/DisplayPADMac" "$APP/Contents/MacOS/"
cp "$ROOT/Mac/DisplayPADMac/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Images/DisplayPAD-branding/macos/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Exigence de désignation fixe : l'autorisation TCC survit aux recompilations
codesign --force --deep --sign - --identifier com.displaypad.mac \
  -r='designated => identifier "com.displaypad.mac"' "$APP"
echo "OK : $APP"
