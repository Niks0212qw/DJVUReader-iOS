#!/bin/bash
set -e

# Script to create XCFramework for djvulibre
# This allows using different libraries for device and simulator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
XCFRAMEWORK_DIR="$SCRIPT_DIR/DJVUReader-iOS/LibDJVU"

echo "🔧 Creating XCFramework for djvulibre..."

# Clean previous XCFramework
if [ -d "$XCFRAMEWORK_DIR/libdjvulibre.xcframework" ]; then
    rm -rf "$XCFRAMEWORK_DIR/libdjvulibre.xcframework"
fi

# Create temporary frameworks for each platform
TEMP_DIR="$BUILD_DIR/temp_frameworks"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Create iOS Device framework
echo "📱 Creating iOS Device framework..."
DEVICE_FRAMEWORK="$TEMP_DIR/iOS/libdjvulibre.framework"
mkdir -p "$DEVICE_FRAMEWORK"
cp "$BUILD_DIR/build-device-arm64/install/lib/libdjvulibre.a" "$DEVICE_FRAMEWORK/libdjvulibre"
mkdir -p "$DEVICE_FRAMEWORK/Headers"
cp -r "$BUILD_DIR/build-device-arm64/install/include/"* "$DEVICE_FRAMEWORK/Headers/"

# Create iOS Simulator framework
echo "🖥️  Creating iOS Simulator framework..."
SIMULATOR_FRAMEWORK="$TEMP_DIR/iOS-simulator/libdjvulibre.framework"
mkdir -p "$SIMULATOR_FRAMEWORK"

# Create universal simulator library
lipo -create \
    "$BUILD_DIR/build-simulator-arm64/install/lib/libdjvulibre.a" \
    "$BUILD_DIR/build-simulator-x86_64/install/lib/libdjvulibre.a" \
    -output "$SIMULATOR_FRAMEWORK/libdjvulibre"

mkdir -p "$SIMULATOR_FRAMEWORK/Headers"
cp -r "$BUILD_DIR/build-simulator-arm64/install/include/"* "$SIMULATOR_FRAMEWORK/Headers/"

# Create Info.plist for both frameworks
create_info_plist() {
    local framework_path=$1
    cat > "$framework_path/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>libdjvulibre</string>
    <key>CFBundleIdentifier</key>
    <string>org.djvu.libdjvulibre</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>libdjvulibre</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>3.5.28</string>
    <key>CFBundleVersion</key>
    <string>3.5.28</string>
</dict>
</plist>
EOF
}

create_info_plist "$DEVICE_FRAMEWORK"
create_info_plist "$SIMULATOR_FRAMEWORK"

# Create XCFramework
echo "🔗 Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "$DEVICE_FRAMEWORK" \
    -framework "$SIMULATOR_FRAMEWORK" \
    -output "$XCFRAMEWORK_DIR/libdjvulibre.xcframework"

# Clean up temporary frameworks
rm -rf "$TEMP_DIR"

# Remove old static libraries
rm -f "$XCFRAMEWORK_DIR/lib/libdjvulibre.a"
rm -f "$XCFRAMEWORK_DIR/lib/libdjvulibre_simulator.a"

echo "✅ XCFramework created successfully!"
echo "📍 Location: $XCFRAMEWORK_DIR/libdjvulibre.xcframework"

# Verify the XCFramework
echo "📊 XCFramework info:"
xcodebuild -checkFirstLaunchStatus
find "$XCFRAMEWORK_DIR/libdjvulibre.xcframework" -name "*.a" -exec lipo -info {} \;

echo ""
echo "🎯 Next steps:"
echo "1. The XCFramework is ready to use"
echo "2. Xcode will automatically select the correct library for each platform"
echo "3. You can now build for both device and simulator"
echo ""