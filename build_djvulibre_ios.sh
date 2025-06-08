#!/bin/bash
set -e

# Build script for djvulibre iOS library
# This script downloads and compiles djvulibre for iOS architectures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DJVULIBRE_VERSION="3.5.28"
DJVULIBRE_URL="https://sourceforge.net/projects/djvu/files/DjVuLibre/$DJVULIBRE_VERSION/djvulibre-$DJVULIBRE_VERSION.tar.gz"

# iOS deployment target
IOS_MIN_VERSION="12.0"

# Architectures to build for simulator only (for development)
ARCHS=("arm64-simulator" "x86_64-simulator")

echo "🏗️  Building djvulibre $DJVULIBRE_VERSION for iOS"
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

# Build for each architecture
for ARCH in "${ARCHS[@]}"; do
    echo "🔨 Building for architecture: $ARCH"
    
    BUILD_ARCH_DIR="$BUILD_DIR/build-$ARCH"
    mkdir -p "$BUILD_ARCH_DIR"
    
    # Set up environment for this architecture
    if [ "$ARCH" = "arm64-simulator" ]; then
        SDK="iphonesimulator"
        HOST="arm-apple-darwin"
        ACTUAL_ARCH="arm64"
        CFLAGS="-arch arm64 -mios-simulator-version-min=$IOS_MIN_VERSION -isysroot $DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
    else
        SDK="iphonesimulator"
        HOST="x86_64-apple-darwin"
        ACTUAL_ARCH="x86_64"
        CFLAGS="-arch x86_64 -mios-simulator-version-min=$IOS_MIN_VERSION -isysroot $DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
    fi
    
    # Copy source for this architecture
    cp -r "djvulibre-$DJVULIBRE_VERSION" "$BUILD_ARCH_DIR/djvulibre"
    cd "$BUILD_ARCH_DIR/djvulibre"
    
    # Configure for iOS
    export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    export CFLAGS="$CFLAGS -fPIC"
    export CXXFLAGS="$CFLAGS -fPIC"
    export LDFLAGS="-arch $ACTUAL_ARCH"
    
    echo "  Configuring for $ARCH..."
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
    
    echo "  Building $ARCH..."
    make -j$(sysctl -n hw.ncpu)
    
    echo "  Installing $ARCH..."
    make install
    
    cd "$BUILD_DIR"
done

# Create universal libraries
echo "🔗 Creating universal libraries..."
UNIVERSAL_DIR="$BUILD_DIR/universal"
mkdir -p "$UNIVERSAL_DIR/lib"
mkdir -p "$UNIVERSAL_DIR/include"

# Copy headers from first architecture
cp -r "$BUILD_DIR/build-arm64-simulator/install/include/"* "$UNIVERSAL_DIR/include/"

# Create universal static libraries
for lib in libdjvulibre.a; do
    echo "  Creating universal $lib..."
    lipo -create \
        "$BUILD_DIR/build-arm64-simulator/install/lib/$lib" \
        "$BUILD_DIR/build-x86_64-simulator/install/lib/$lib" \
        -output "$UNIVERSAL_DIR/lib/$lib"
done

# Copy to project directory
echo "📁 Copying libraries to project..."
PROJECT_LIB_DIR="$SCRIPT_DIR/DJVUReader-iOS/LibDJVU"
mkdir -p "$PROJECT_LIB_DIR/lib"
mkdir -p "$PROJECT_LIB_DIR/include"

cp "$UNIVERSAL_DIR/lib/libdjvulibre.a" "$PROJECT_LIB_DIR/lib/"
cp -r "$UNIVERSAL_DIR/include/"* "$PROJECT_LIB_DIR/include/"

echo "✅ djvulibre build complete!"
echo "Library: $PROJECT_LIB_DIR/lib/libdjvulibre.a"
echo "Headers: $PROJECT_LIB_DIR/include/"

# Verify the library
echo "📊 Library info:"
file "$PROJECT_LIB_DIR/lib/libdjvulibre.a"
lipo -info "$PROJECT_LIB_DIR/lib/libdjvulibre.a"

echo ""
echo "🎯 Next steps:"
echo "1. Add libdjvulibre.a to your Xcode project"
echo "2. Update header search paths to include LibDJVU/include"
echo "3. Link against the static library in Build Settings"
echo ""