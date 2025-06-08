#!/bin/bash
set -e

# Universal build script for djvulibre iOS library
# This script builds djvulibre for both iOS device and simulator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DJVULIBRE_VERSION="3.5.28"
DJVULIBRE_URL="https://sourceforge.net/projects/djvu/files/DjVuLibre/$DJVULIBRE_VERSION/djvulibre-$DJVULIBRE_VERSION.tar.gz"

# iOS deployment target
IOS_MIN_VERSION="15.0"

# Architectures to build for both device and simulator
DEVICE_ARCHS=("arm64")
SIMULATOR_ARCHS=("arm64" "x86_64")

echo "🏗️  Building djvulibre $DJVULIBRE_VERSION for iOS (Universal)"
echo "Script directory: $SCRIPT_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download djvulibre if not exists
if [ ! -f "djvulibre-$DJVULIBRE_VERSION.tar.gz" ]; then
    echo "📥 Downloading djvulibre..."
    curl -L "$DJVULIBRE_URL" -o "djvulibre-$DJVULIBRE_VERSION.tar.gz"
fi

# Extract if not exists
if [ ! -d "djvulibre-$DJVULIBRE_VERSION" ]; then
    echo "📦 Extracting djvulibre..."
    tar -xzf "djvulibre-$DJVULIBRE_VERSION.tar.gz"
fi

# Get Xcode developer directory
DEVELOPER_DIR=$(xcode-select -p)
echo "Using Xcode at: $DEVELOPER_DIR"

# Function to build for a specific platform and architecture
build_for_arch() {
    local PLATFORM=$1
    local ARCH=$2
    
    echo "🔨 Building for $PLATFORM/$ARCH"
    
    BUILD_ARCH_DIR="$BUILD_DIR/build-$PLATFORM-$ARCH"
    mkdir -p "$BUILD_ARCH_DIR"
    
    # Set up environment for this platform/architecture
    if [ "$PLATFORM" = "device" ]; then
        SDK="iphoneos"
        SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        HOST="arm-apple-darwin"
        MIN_VERSION_FLAG="-miphoneos-version-min=$IOS_MIN_VERSION"
    else # simulator
        SDK="iphonesimulator"
        SDK_PATH="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        if [ "$ARCH" = "arm64" ]; then
            HOST="arm-apple-darwin"
        else
            HOST="x86_64-apple-darwin"
        fi
        MIN_VERSION_FLAG="-mios-simulator-version-min=$IOS_MIN_VERSION"
    fi
    
    # Copy source for this architecture
    cp -r "djvulibre-$DJVULIBRE_VERSION" "$BUILD_ARCH_DIR/djvulibre"
    cd "$BUILD_ARCH_DIR/djvulibre"
    
    # Configure environment
    export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    export CFLAGS="-arch $ARCH $MIN_VERSION_FLAG -isysroot $SDK_PATH -fPIC -O2"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $ARCH $MIN_VERSION_FLAG -isysroot $SDK_PATH"
    
    echo "  Configuring for $PLATFORM/$ARCH..."
    ./configure \
        --host="$HOST" \
        --prefix="$BUILD_ARCH_DIR/install" \
        --enable-static \
        --disable-shared \
        --disable-desktopfiles \
        --disable-xmltools \
        --disable-pthread \
        --without-jpeg \
        --without-tiff \
        --without-qt \
        --without-x \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS"
    
    echo "  Building $PLATFORM/$ARCH..."
    make -j$(sysctl -n hw.ncpu)
    
    echo "  Installing $PLATFORM/$ARCH..."
    make install
    
    cd "$BUILD_DIR"
}

# Build for all device architectures
echo "📱 Building for iOS Device..."
for ARCH in "${DEVICE_ARCHS[@]}"; do
    build_for_arch "device" "$ARCH"
done

# Build for all simulator architectures
echo "🖥️  Building for iOS Simulator..."
for ARCH in "${SIMULATOR_ARCHS[@]}"; do
    build_for_arch "simulator" "$ARCH"
done

# Create universal libraries
echo "🔗 Creating universal libraries..."
UNIVERSAL_DIR="$BUILD_DIR/universal"
mkdir -p "$UNIVERSAL_DIR/lib"
mkdir -p "$UNIVERSAL_DIR/include"

# Copy headers from first architecture
cp -r "$BUILD_DIR/build-device-arm64/install/include/"* "$UNIVERSAL_DIR/include/"

# Collect all library files
LIBRARY_FILES=()
for ARCH in "${DEVICE_ARCHS[@]}"; do
    LIBRARY_FILES+=("$BUILD_DIR/build-device-$ARCH/install/lib/libdjvulibre.a")
done
for ARCH in "${SIMULATOR_ARCHS[@]}"; do
    LIBRARY_FILES+=("$BUILD_DIR/build-simulator-$ARCH/install/lib/libdjvulibre.a")
done

# Create universal static library
echo "  Creating universal libdjvulibre.a..."
lipo -create "${LIBRARY_FILES[@]}" -output "$UNIVERSAL_DIR/lib/libdjvulibre.a"

# Copy to project directory
echo "📁 Copying libraries to project..."
PROJECT_LIB_DIR="$SCRIPT_DIR/DJVUReader-iOS/LibDJVU"
mkdir -p "$PROJECT_LIB_DIR/lib"
mkdir -p "$PROJECT_LIB_DIR/include"

cp "$UNIVERSAL_DIR/lib/libdjvulibre.a" "$PROJECT_LIB_DIR/lib/"
cp -r "$UNIVERSAL_DIR/include/"* "$PROJECT_LIB_DIR/include/"

echo "✅ djvulibre universal build complete!"
echo "Library: $PROJECT_LIB_DIR/lib/libdjvulibre.a"
echo "Headers: $PROJECT_LIB_DIR/include/"

# Verify the library
echo "📊 Library info:"
file "$PROJECT_LIB_DIR/lib/libdjvulibre.a"
lipo -info "$PROJECT_LIB_DIR/lib/libdjvulibre.a"

echo ""
echo "🎯 The library now supports:"
echo "- iOS Device: arm64"
echo "- iOS Simulator: arm64, x86_64"
echo ""
echo "You can now run on both simulator and real devices!"
echo ""