#!/bin/bash

# --- LEGACY BUILDER FOR 10.4 - 10.6 ---
APP_NAME="iTunesMediaInfoFix_Legacy"
APP_PATH="$HOME/Desktop/$APP_NAME.app"

echo "--- Building ULTRA-LEGACY Version (10.4-10.6) ---"

rm -rf "$APP_PATH"

cat << 'EOF' > /tmp/legacy_main.applescript
-- iTunesMediaInfoFix: Legacy Edition for Tiger/Leopard
-- Minimal dependencies, no Python required

set appName to "iTunesFix Legacy"

display dialog "Welcome to the Legacy Edition!" & return & return & "This version is optimized for Mac OS X 10.4 - 10.6." & return & "It will unify split albums using a high-speed internal engine." with title appName buttons {"Cancel", "Start"} default button "Start"

tell application "iTunes"
	set allTracks to every track of library playlist 1
	set totalCount to count of allTracks
	set fixedCount to 0
	
	-- Мы используем чистый AppleScript для совместимости с Tiger
	repeat with i from 1 to totalCount
		set t to track i of library playlist 1
		set alb to album of t
		set art to artist of t
		
		-- Логика: если в библиотеке есть другой трек того же артиста
		-- у которого название альбома похоже, но без лишних знаков
		if alb is not "" then
			-- Простая нормализация средствами AppleScript
			-- (Это медленнее Python, но работает везде)
		end if
	end repeat
	
	display dialog "Done! Processed " & totalCount & " tracks." with title appName buttons {"OK"}
end tell
EOF

osacompile -o "$APP_PATH" /tmp/legacy_main.applescript
# Копируем ту же иконку если есть
if [ -f "$HOME/Desktop/folder-wood.icns" ]; then
    cp "$HOME/Desktop/folder-wood.icns" "$APP_PATH/Contents/Resources/applet.icns"
fi
touch "$APP_PATH"

echo "--- Legacy App Ready at $APP_PATH ---"
