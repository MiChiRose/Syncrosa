#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: package_installer.sh /path/to/Syncrosa.app /path/to/output-directory}"
DIST_DIR="${2:?Specify an output directory}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid Syncrosa version: $VERSION" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/codesign --verify --deep "$APP_PATH"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
STAGE="$(mktemp -d "$DIST_DIR/.syncrosa-installer.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/payload"
/usr/bin/ditto "$APP_PATH" "$STAGE/payload/Syncrosa.app"
ln -s /Applications "$STAGE/payload/Applications"
# Apply the Finder icon positions without sending Apple Events during a build.
/usr/bin/ditto "$SCRIPT_DIR/InstallerLayout.store" "$STAGE/payload/.DS_Store"

DMG_NAME="Syncrosa_Cocoa_v${VERSION}.dmg"
/usr/bin/hdiutil create -quiet -srcfolder "$STAGE/payload" -volname "Syncrosa $VERSION" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$STAGE/$DMG_NAME"
/usr/bin/hdiutil verify -quiet "$STAGE/$DMG_NAME"
mv -f "$STAGE/$DMG_NAME" "$DIST_DIR/$DMG_NAME"
echo "Created $DMG_NAME"
