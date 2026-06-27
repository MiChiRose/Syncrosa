#!/bin/bash
cd "$(dirname "$0")"
echo "🛠 Building Syncrosa..."
PROJECT="Syncrosa.xcodeproj"
TARGET="Syncrosa"
TEST_TARGET="SyncrosaTests"

rm -rf build

# Detect macOS version to determine build target and patch requirement
OS_VER=$(sw_vers -productVersion)
OS_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
OS_MINOR=$(echo "$OS_VER" | cut -d. -f2)

if [ "$OS_MAJOR" -eq 10 ] && [ "$OS_MINOR" -lt 13 ]; then
    echo "👴 Legacy macOS detected ($OS_VER). Building natively for 10.9..."
    xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -arch x86_64 MACOSX_DEPLOYMENT_TARGET=10.9 clean build | tee build.log
    BUILD_STATUS=${PIPESTATUS[0]}
    USE_PATCH=false
else
    echo "💻 Modern macOS detected ($OS_VER). Building with 10.13 target and patching to 10.9..."
    xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -arch x86_64 MACOSX_DEPLOYMENT_TARGET=10.13 clean build | tee build.log
    BUILD_STATUS=${PIPESTATUS[0]}
    USE_PATCH=true
fi

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ Build Successful!"
    APP_PATH=$(find build -name "*.app" -type d | head -n 1)
    cp -R "$APP_PATH" .
    
    if [ "$USE_PATCH" = true ]; then
        echo "⚙️ Patching minimum deployment version to 10.9..."
        python3 patch_binary.py Syncrosa.app/Contents/MacOS/Syncrosa
        codesign --force --deep --sign - Syncrosa.app
    fi
    
    echo "Creating distribution ZIP..."
    rm -f "$HOME/Desktop/Syncrosa_Cocoa_v3.2.0.zip"
    zip -ry "$HOME/Desktop/Syncrosa_Cocoa_v3.2.0.zip" Syncrosa.app
    rm -rf Syncrosa.app
    echo "✅ Syncrosa_Cocoa_v3.2.0.zip successfully created on Desktop!"
else
    echo "❌ Build Failed. Check build.log"
    exit 1
fi

echo "🧪 Compiling Tests..."
xcodebuild -project "$PROJECT" -target "$TEST_TARGET" -configuration Debug build | tee test.log
