#!/bin/bash
set -euo pipefail

# Переходим в папку проекта
cd "$(dirname "$0")"

echo "🛠 Building Syncrosa (SwiftUI)..."

VERSION_FILE="../VERSION"
if [ -n "${SYNCROSA_VERSION:-}" ]; then
    APP_VERSION="$SYNCROSA_VERSION"
else
    if [ ! -f "$VERSION_FILE" ]; then
        echo "❌ VERSION file not found at $VERSION_FILE"
        exit 1
    fi
    APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
if [ -z "$APP_VERSION" ]; then
    echo "❌ VERSION is empty."
    exit 1
fi
DIST_DIR="${SYNCROSA_DIST_DIR:-$HOME/Desktop}"
DIST_ZIP="$DIST_DIR/Syncrosa_SwiftUI_v${APP_VERSION}.zip"

# Удаляем старую сборку если есть
rm -rf Syncrosa.app libSyncrosa.dylib libSyncrosa.dylib.dSYM

# Собираем исполняемый файл для Apple Silicon
swift build -c release --arch arm64

# Определяем путь к бинарнику
BINARY_PATH=$(swift build -c release --arch arm64 --show-bin-path)/Syncrosa

# Создаем структуру .app
mkdir -p Syncrosa.app/Contents/MacOS
mkdir -p Syncrosa.app/Contents/Resources

# Копируем бинарник
cp "$BINARY_PATH" Syncrosa.app/Contents/MacOS/

# Копируем иконку (если есть)
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" Syncrosa.app/Contents/Resources/AppIcon.icns
fi

# Создаем Info.plist
cat > Syncrosa.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Syncrosa</string>
    <key>CFBundleIdentifier</key>
    <string>com.michirose.Syncrosa</string>
    <key>CFBundleName</key>
    <string>Syncrosa</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Syncrosa needs to access Music.app to read your playlists.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Syncrosa needs access to your USB drive to export music files.</string>
</dict>
</plist>
EOF

# Подписываем приложение (ad-hoc) с entitlements
if [ -f "Syncrosa.entitlements" ]; then
    codesign --force --options runtime --entitlements Syncrosa.entitlements --sign - Syncrosa.app
else
    codesign --force --sign - Syncrosa.app
fi

echo "Creating distribution ZIP..."
mkdir -p "$DIST_DIR"
rm -f "$DIST_ZIP"
ditto -c -k --norsrc --keepParent Syncrosa.app "$DIST_ZIP"
rm -rf Syncrosa.app libSyncrosa.dylib libSyncrosa.dylib.dSYM

echo "✅ $(basename "$DIST_ZIP") successfully created at $DIST_ZIP"
