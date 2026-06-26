#!/bin/bash

# --- ИНСТРУКЦИЯ ---
# ЗАПУСКАТЬ СТРОГО НА СТАРОМ MAC (10.9 - 10.13)
# ------------------

APP_NAME="Syncrosa"
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_PATH="$WORK_DIR/$APP_NAME.app"

echo "--- Building Native $APP_NAME PRO (AI + Fixer) for Mavericks ---"

# 1. Очистка старой версии
rm -rf "$APP_PATH"

# 2. СОЗДАЕМ ЧИСТУЮ СТРУКТУРУ MAC APP BUNDLE
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# 3. INFO.PLIST (Паспорт приложения)
cat << 'EOF' > "$APP_PATH/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Syncrosa</string>
    <key>CFBundleIconFile</key>
    <string>appIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.michirose.syncrosa-python</string>
    <key>CFBundleName</key>
    <string>Syncrosa</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.2.0</string>
    <key>CFBundleVersion</key>
    <string>3.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.9</string>
</dict>
</plist>
EOF

# 4. СОЗДАЕМ ИСПОЛНЯЕМЫЙ ФАЙЛ (МАГИЯ ПИТОНА)
cat << 'EOF' > "$APP_PATH/Contents/MacOS/$APP_NAME"
#!/bin/bash
# Find the best python version available
if [ -x "/usr/local/bin/python2.7" ]; then
    PYTHON_EXE="/usr/local/bin/python2.7"
elif [ -x "/usr/bin/python" ]; then
    PYTHON_EXE="/usr/bin/python"
elif [ -x "/usr/bin/python3" ]; then
    PYTHON_EXE="/usr/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_EXE="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    PYTHON_EXE="$(command -v python)"
else
    PYTHON_EXE="python"
fi

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES_DIR="$BASE_DIR/../Resources"
export PYTHONPATH="$RESOURCES_DIR:$PYTHONPATH"

exec "$PYTHON_EXE" "$RESOURCES_DIR/main.py"
EOF

chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# 5. КОПИРУЕМ ЛОГИКУ ПРИЛОЖЕНИЯ (ВСЕ ПАКЕТЫ)
echo "Injecting modular python logic..."
cp "$WORK_DIR/main.py" "$APP_PATH/Contents/Resources/"
cp -R "$WORK_DIR/core" "$APP_PATH/Contents/Resources/"
cp -R "$WORK_DIR/ui" "$APP_PATH/Contents/Resources/"
cp -R "$WORK_DIR/features" "$APP_PATH/Contents/Resources/"

# 6. ПРИМЕНЯЕМ ИКОНКУ
echo "Applying custom icon..."
ICON_SRC=""
[ -f "$WORK_DIR/AppIcon.icns" ] && ICON_SRC="$WORK_DIR/AppIcon.icns"

if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/appIcon.icns"
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found, falling back to iTunes icon..."
    cp "/Applications/iTunes.app/Contents/Resources/iTunes.icns" "$APP_PATH/Contents/Resources/appIcon.icns" 2>/dev/null
fi

# 7. ФИНАЛИЗАЦИЯ ПРАВ
echo "Finalizing permissions..."
chmod -R 755 "$APP_PATH"
xattr -rc "$APP_PATH" 2>/dev/null

# 8. ОБНОВЛЕНИЕ КЭША ИКОНОК (МАГИЯ)
echo "Refreshing Finder icon cache..."
/usr/bin/touch "$APP_PATH"
/usr/bin/touch "$APP_PATH/Contents/Info.plist"
/usr/bin/touch "$APP_PATH/Contents/Resources/appIcon.icns"
/usr/bin/touch "$APP_PATH/Contents/Resources/AppIcon.icns"

# Force Mac OS to reload the app bundle metadata
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"

# 9. УПАКОВКА В ZIP
echo "Creating distribution ZIP..."
rm -f "$HOME/Desktop/Syncrosa_Python_v3.2.0.zip"
cd "$WORK_DIR"
zip -ry "$HOME/Desktop/Syncrosa_Python_v3.2.0.zip" "$APP_NAME.app"
rm -rf "$APP_PATH"

echo "--- SUCCESS! ---"
echo "Ready: Syncrosa_Python_v3.2.0.zip on your Desktop."
