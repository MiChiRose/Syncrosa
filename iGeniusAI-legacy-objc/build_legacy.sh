#!/bin/bash
cd "$(dirname "$0")"
echo "🛠 Building iGeniusAI-legacy-objc..."
PROJECT="iGeniusAI-legacy-objc.xcodeproj"
SCHEME="iGeniusAI-legacy-objc"

rm -rf build
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -arch x86_64 clean build | tee build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build Successful!"
    APP_PATH=$(find build -name "*.app" -type d | head -n 1)
    cp -R "$APP_PATH" .
    echo "📦 Package ready: $(basename "$APP_PATH")"
else
    echo "❌ Build Failed. Check build.log"
    exit 1
fi

echo "🧪 Running Tests..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug test | tee test.log
