#!/bin/bash

# Переходим в папку проекта
cd "$(dirname "$0")"

echo "🏗 Building iGeniusAI-arm (SwiftUI)..."

# Удаляем старую сборку если есть
rm -rf iGeniusAI-arm.app

# Собираем исполняемый файл для Apple Silicon
swift build -c release --arch arm64

# Определяем путь к бинарнику
BINARY_PATH=$(swift build -c release --arch arm64 --show-bin-path)/iGeniusAI-arm

# Создаем структуру .app
mkdir -p iGeniusAI-arm.app/Contents/MacOS
mkdir -p iGeniusAI-arm.app/Contents/Resources

# Копируем бинарник
cp "$BINARY_PATH" iGeniusAI-arm.app/Contents/MacOS/

# Копируем иконку (если есть)
if [ -f "genius_atom.icns" ]; then
    cp "genius_atom.icns" iGeniusAI-arm.app/Contents/Resources/AppIcon.icns
fi

# Создаем Info.plist
cat > iGeniusAI-arm.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>iGeniusAI-arm</string>
    <key>CFBundleIdentifier</key>
    <string>com.igeniusai.modern</string>
    <key>CFBundleName</key>
    <string>iGeniusAI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Подписываем приложение (ad-hoc) с entitlements
if [ -f "iGeniusAI-arm.entitlements" ]; then
    codesign --force --options runtime --entitlements iGeniusAI-arm.entitlements --sign - iGeniusAI-arm.app
else
    codesign --force --sign - iGeniusAI-arm.app
fi

echo "✅ iGeniusAI-arm.app successfully created!"
open .
