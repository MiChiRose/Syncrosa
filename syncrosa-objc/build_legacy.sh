#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🛠 Building Syncrosa legacy Objective-C..."

PROJECT="Syncrosa.xcodeproj"
TARGET="Syncrosa"
TEST_TARGET="SyncrosaTests"
APP_NAME="Syncrosa.app"
EXECUTABLE_NAME="Syncrosa"
DEPLOYMENT_TARGET="10.9"
ARCH="x86_64"
BUILD_ROOT="build-legacy"
DIST_ZIP="$HOME/Desktop/Syncrosa_Cocoa_v3.2.0.zip"
UNSIGNED_DIST_ZIP="$HOME/Desktop/Syncrosa_Cocoa_v3.2.0_unsigned.zip"
UNSIGNED_ROOT="$BUILD_ROOT/UnsignedDist"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode_6.2.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode_6.2.app/Contents/Developer"
fi

XCODEBUILD=$(xcrun -f xcodebuild 2>/dev/null || command -v xcodebuild || true)
if [ -z "$XCODEBUILD" ]; then
    echo "❌ xcodebuild was not found."
    exit 1
fi

SDK_NAME="macosx"
if "$XCODEBUILD" -showsdks 2>/dev/null | grep -q "macosx10\.9"; then
    SDK_NAME="macosx10.9"
fi
SDK_ARGS=(-sdk "$SDK_NAME")

rm -rf "$BUILD_ROOT" "$APP_NAME"

COMMON_SETTINGS=(
    "ARCHS=$ARCH"
    "SDKROOT=$SDK_NAME"
    "ONLY_ACTIVE_ARCH=NO"
    "MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
    "CLANG_ENABLE_OBJC_ARC=NO"
    "CLANG_LINK_OBJC_RUNTIME=NO"
    "ENABLE_CODE_COVERAGE=NO"
    "CLANG_ENABLE_CODE_COVERAGE=NO"
    "CLANG_COVERAGE_MAPPING=NO"
    "CLANG_PROFILE_GENERATE=NO"
    "CLANG_INSTRUMENT_FOR_OPTIMIZATION_PROFILING=NO"
    "GCC_PROFILE_GENERATE=NO"
    "GCC_GENERATE_TEST_COVERAGE_FILES=NO"
    "GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO"
    "CODE_SIGNING_ALLOWED=NO"
    "CODE_SIGNING_REQUIRED=NO"
    "CODE_SIGN_IDENTITY="
    "SYMROOT=$BUILD_ROOT"
    "OBJROOT=$BUILD_ROOT/Intermediates"
    "DSTROOT=$BUILD_ROOT/Install"
)

echo "🎯 Targeting OS X $DEPLOYMENT_TARGET ($ARCH)."
echo "🧰 Using $("$XCODEBUILD" -version | tr '\n' ' ') with SDK $SDK_NAME."
echo "⚙️ Legacy mode disables ARC runtime autolinking to avoid modern Xcode libarclite crashes."

set +e
"$XCODEBUILD" \
    -project "$PROJECT" \
    -target "$TARGET" \
    -configuration Release \
    "${SDK_ARGS[@]}" \
    -arch "$ARCH" \
    build \
    "${COMMON_SETTINGS[@]}" 2>&1 | tee build.log
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "❌ Build failed. Check build.log"
    exit 1
fi

APP_PATH="$BUILD_ROOT/Release/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build succeeded, but $APP_PATH was not produced."
    exit 1
fi

ditto "$APP_PATH" "$APP_NAME"

INFO_PLIST="$APP_NAME/Contents/Info.plist"
BINARY_PATH="$APP_NAME/Contents/MacOS/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $DEPLOYMENT_TARGET" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $DEPLOYMENT_TARGET" "$INFO_PLIST"

MIN_PLIST=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST")
MIN_MACHO=$(otool -l "$BINARY_PATH" | awk '/LC_VERSION_MIN_MACOSX/{found=1} found && /version /{print $2; exit}')

if [ "$MIN_PLIST" != "$DEPLOYMENT_TARGET" ]; then
    echo "❌ Info.plist minimum system version is $MIN_PLIST, expected $DEPLOYMENT_TARGET."
    exit 1
fi

if [ "$MIN_MACHO" != "$DEPLOYMENT_TARGET" ]; then
    echo "❌ Mach-O minimum system version is $MIN_MACHO, expected $DEPLOYMENT_TARGET."
    exit 1
fi

if otool -l "$BINARY_PATH" | grep -q "__LLVM_COV"; then
    echo "❌ Release binary contains LLVM coverage sections."
    exit 1
fi

if otool -l "$BINARY_PATH" | grep -E -q "__LLVM|__llvm|__llvm_prf"; then
    echo "❌ Release binary contains LLVM/profile sections."
    exit 1
fi

if strings -a "$BINARY_PATH" | grep -E -q "__llvm_prf|libclang_rt\\.profile|default\\.profraw"; then
    echo "❌ Release binary contains LLVM profile runtime references."
    exit 1
fi

mkdir -p "$UNSIGNED_ROOT"
ditto "$APP_NAME" "$UNSIGNED_ROOT/$APP_NAME"
codesign --remove-signature "$UNSIGNED_ROOT/$APP_NAME" 2>/dev/null || true
rm -rf "$UNSIGNED_ROOT/$APP_NAME/Contents/_CodeSignature"

UNSIGNED_BINARY_PATH="$UNSIGNED_ROOT/$APP_NAME/Contents/MacOS/$EXECUTABLE_NAME"
if otool -l "$UNSIGNED_BINARY_PATH" | grep -q "LC_CODE_SIGNATURE"; then
    echo "❌ Unsigned fallback still contains an LC_CODE_SIGNATURE load command."
    exit 1
fi

echo "🔒 Re-signing application bundle..."
xattr -cr "$APP_NAME" 2>/dev/null || true
codesign --force --deep --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

echo "📦 Creating distribution ZIP..."
rm -f "$DIST_ZIP"
ditto -c -k --norsrc --keepParent "$APP_NAME" "$DIST_ZIP"

echo "📦 Creating unsigned fallback ZIP for OS X 10.9..."
rm -f "$UNSIGNED_DIST_ZIP"
(
    cd "$UNSIGNED_ROOT"
    ditto -c -k --norsrc --keepParent "$APP_NAME" "$UNSIGNED_DIST_ZIP"
)
rm -rf "$APP_NAME" "$UNSIGNED_ROOT"

echo "✅ Syncrosa_Cocoa_v3.2.0.zip successfully created on Desktop!"
echo "✅ Syncrosa_Cocoa_v3.2.0_unsigned.zip fallback created on Desktop!"

echo "🧪 Compiling tests..."
set +e
"$XCODEBUILD" \
    -project "$PROJECT" \
    -target "$TEST_TARGET" \
    -configuration Debug \
    "${SDK_ARGS[@]}" \
    -arch "$ARCH" \
    "${COMMON_SETTINGS[@]}" \
    "SYMROOT=$BUILD_ROOT/tests" \
    "OBJROOT=$BUILD_ROOT/tests/Intermediates" \
    build 2>&1 | tee test.log
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [ "$TEST_STATUS" -ne 0 ]; then
    echo "⚠️ Test target did not compile. App ZIP was still created."
else
    echo "✅ Tests compiled."
fi
