#!/bin/bash
cd "$(dirname "$0")"
echo "🛠 Building Syncrosa..."
PROJECT="Syncrosa.xcodeproj"
TARGET="Syncrosa"
TEST_TARGET="SyncrosaTests"

rm -rf build
# Use -target instead of -scheme because schemes were ignored in git (xcuserdata)
xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -arch x86_64 clean build | tee build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build Successful!"
    APP_PATH=$(find build -name "*.app" -type d | head -n 1)
    cp -R "$APP_PATH" .
    echo "Creating distribution ZIP..."
    rm -f "$HOME/Desktop/Syncrosa_Cocoa_Legacy.zip"
    zip -ry "$HOME/Desktop/Syncrosa_Cocoa_Legacy.zip" Syncrosa.app
    rm -rf Syncrosa.app
    echo "✅ Syncrosa_Cocoa_Legacy.zip successfully created on Desktop!"
else
    echo "❌ Build Failed. Check build.log"
    exit 1
fi

echo "🧪 Compiling Tests..."
xcodebuild -project "$PROJECT" -target "$TEST_TARGET" -configuration Debug build | tee test.log
