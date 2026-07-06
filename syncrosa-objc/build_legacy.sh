#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "🛠 Building Syncrosa legacy Objective-C..."

PROJECT="Syncrosa.xcodeproj"
TARGET="Syncrosa"
TEST_TARGET="SyncrosaTests"
SCHEME="${SYNCROSA_SCHEME:-$TARGET}"
APP_NAME="Syncrosa.app"
EXECUTABLE_NAME="Syncrosa"
DEPLOYMENT_TARGET="10.9"
ARCH="x86_64"
BUILD_ROOT="build-legacy"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
VERSION_FILE="../VERSION"
if [ -n "${SYNCROSA_VERSION:-}" ]; then
    APP_VERSION="$SYNCROSA_VERSION"
elif [ -f "$VERSION_FILE" ]; then
    APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
elif [ -f "Sources/Info.plist" ]; then
    APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "Sources/Info.plist" 2>/dev/null || true)"
elif command -v git >/dev/null 2>&1; then
    APP_VERSION="$(cd .. && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
else
    APP_VERSION=""
fi
if [ -z "$APP_VERSION" ]; then
    echo "❌ Syncrosa version is not set. Export SYNCROSA_VERSION=3.2.1 before building."
    exit 1
fi
DIST_DIR="${SYNCROSA_DIST_DIR:-$HOME/Desktop}"
DIST_ZIP="$DIST_DIR/Syncrosa_Cocoa_v${APP_VERSION}.zip"

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
    "CLANG_MODULE_CACHE_PATH=$BUILD_ROOT/ModuleCache.noindex"
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
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_VERSION" "$INFO_PLIST"

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

echo "🔒 Re-signing application bundle..."
xattr -cr "$APP_NAME" 2>/dev/null || true
codesign --force --deep --sign - "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

echo "🧪 Compiling tests..."
"$XCODEBUILD" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH/tests" \
    "${SDK_ARGS[@]}" \
    -arch "$ARCH" \
    "${COMMON_SETTINGS[@]}" \
    "SYMROOT=$BUILD_ROOT/tests" \
    "OBJROOT=$BUILD_ROOT/tests/Intermediates" \
    build-for-testing 2>&1 | tee test.log

echo "✅ Tests compiled."

echo "📦 Creating distribution ZIP..."
mkdir -p "$DIST_DIR"
rm -f "$DIST_ZIP"
ditto -c -k --norsrc --keepParent "$APP_NAME" "$DIST_ZIP"

rm -rf "$APP_NAME"

echo "✅ $(basename "$DIST_ZIP") successfully created at $DIST_ZIP"
