#!/bin/bash
cd "$(dirname "$0")"
echo "🛠 Building iGeniusAI-legacy-objc..."
PROJECT="iGeniusAI-legacy-objc.xcodeproj"
TARGET="iGeniusAI-legacy-objc"
TEST_TARGET="iGeniusAI-legacy-objcTests"

rm -rf build
# Use -target instead of -scheme because schemes were ignored in git (xcuserdata)
xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -arch x86_64 clean build | tee build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build Successful!"
    APP_PATH=$(find build -name "*.app" -type d | head -n 1)
    cp -R "$APP_PATH" .
    echo "📦 Package ready: $(basename "$APP_PATH")"
else
    echo "❌ Build Failed. Check build.log"
    exit 1
fi

echo "🧪 Compiling Tests..."
xcodebuild -project "$PROJECT" -target "$TEST_TARGET" -configuration Debug build | tee test.log
