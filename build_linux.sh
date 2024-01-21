#!/bin/bash
# Toolchain download information
TOOLCHAIN_VER="v22_clang-16.0.6-centos7"
TOOLCHAIN_URL="https://cdn.unrealengine.com/Toolchain_Linux/native-linux-${TOOLCHAIN_VER}.tar.gz"
TOOLCHAIN_ARCHIVE="native-linux-${TOOLCHAIN_VER}.tar.gz"
TOOLCHAIN_DIR="unreal_toolchain"

# Download the Unreal Engine Linux Toolchain if it's not already present
if [ ! -d "$TOOLCHAIN_DIR" ]; then
	echo "Downloading Unreal Engine Linux Toolchain..."
	wget "$TOOLCHAIN_URL"

	echo "Extracting Toolchain..."
	mkdir "$TOOLCHAIN_DIR"
	tar -xzvf "$TOOLCHAIN_ARCHIVE" -C "$TOOLCHAIN_DIR"
	rm "$TOOLCHAIN_ARCHIVE"
fi

# Set the path to the extracted toolchain
UE_TOOLCHAIN_PATH="$PWD/$TOOLCHAIN_DIR/$TOOLCHAIN_VER/x86_64-unknown-linux-gnu"

rm -rf "build"
rm -rf "install"

# Set the compilers to use Unreal's versions
export CC="$UE_TOOLCHAIN_PATH/bin/clang"
export CXX="$UE_TOOLCHAIN_PATH/bin/clang++"

# Configure sentry-native with Unreal's toolchain
cmake -B "build" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DSENTRY_BACKEND=crashpad \
	-DSENTRY_TRANSPORT=none \
	-DBUILD_SHARED_LIBS=ON \
	-DCRASHPAD_ZLIB_SYSTEM=OFF

#	-DCMAKE_SYSROOT="$UE_TOOLCHAIN_PATH" \
#-DCMAKE_TOOLCHAIN_FILE="$UE_TOOLCHAIN_PATH/cmake/UE4Toolchain.cmake"

# Build and install sentry-native
cmake --build build --parallel --config RelWithDebInfo
cmake --install build --prefix install --config Release

7z a Sentry-Native-Linux "./install/*"