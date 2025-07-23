#!/bin/bash
# Toolchain download information
TOOLCHAIN_VER="v25_clang-18.1.0-rockylinux8"
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
#export CC="$UE_TOOLCHAIN_PATH/bin/clang"
#export CXX="$UE_TOOLCHAIN_PATH/bin/clang++"

# Install Zlib in Sysroot
ZLIB_VER="1.3.1"
ZLIB_URL="https://zlib.net/zlib-$ZLIB_VER.tar.gz"
wget "$ZLIB_URL"
tar xf "zlib-$ZLIB_VER.tar.gz"
rm "zlib-$ZLIB_VER.tar.gz"
cd "zlib-$ZLIB_VER"
./configure --prefix="$UE_TOOLCHAIN_PATH/usr"
make -j$(nproc)
make install
cd ..

# Install OpenSSL in Sysroot
OPENSSL_VER="3.5.1"
wget https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz
tar xf openssl-$OPENSSL_VER.tar.gz
rm openssl-$OPENSSL_VER.tar.gz
cd openssl-$OPENSSL_VER
./Configure linux-x86_64 --prefix="$UE_TOOLCHAIN_PATH/usr" no-shared no-shared no-tests no-docs no-docs
make -j$(nproc)
make install_sw
cd ..

# Build ICU
ICU_MAJOR=77
ICU_MINOR=1
ICU_VER="${ICU_MAJOR}_${ICU_MINOR}"
ICU_VER_DASH="${ICU_MAJOR}-${ICU_MINOR}"
ICU_TAR="icu4c-${ICU_VER}-src.tgz"
wget "https://github.com/unicode-org/icu/releases/download/release-${ICU_VER_DASH}/${ICU_TAR}"
tar xf "${ICU_TAR}"
rm "${ICU_TAR}"
cd icu/source
./configure --prefix="$UE_TOOLCHAIN_PATH/usr"
make -j$(nproc)
make install
cd ../..

# Build libpsl version (check https://github.com/rockdaboot/libpsl/releases for latest)
LIBPSL_VER="0.21.5"
wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/libpsl-$LIBPSL_VER.tar.gz
tar xf libpsl-$LIBPSL_VER.tar.gz
rm libpsl-$LIBPSL_VER.tar.gz
cd libpsl-$LIBPSL_VER

# Configure libpsl properly
./configure --prefix="$UE_TOOLCHAIN_PATH/usr" \
    --disable-shared \
    --enable-static \
    --disable-tools \
    --with-libiconv-prefix="$UE_TOOLCHAIN_PATH/usr" \
    --with-libidn2=no \
    --with-libicu="$UE_TOOLCHAIN_PATH/usr"
# Build and install the complete library
make -j$(nproc) install-exec
cd ..

# Install Curl in Sysroot							
CURL_VER="8.15.0"
wget https://curl.se/download/curl-$CURL_VER.tar.gz
tar xf curl-$CURL_VER.tar.gz
cd curl-$CURL_VER
./configure --prefix="$UE_TOOLCHAIN_PATH/usr" \
    --with-zlib="$UE_TOOLCHAIN_PATH/usr" \
    --disable-shared \
    --enable-static \
    --with-openssl="$UE_TOOLCHAIN_PATH/usr" \
    --with-libpsl="$UE_TOOLCHAIN_PATH/usr" \
    PKG_CONFIG_PATH="$UE_TOOLCHAIN_PATH/usr/lib/pkgconfig:$UE_TOOLCHAIN_PATH/usr/lib64/pkgconfig"
make -j$(nproc)
make install
cd ..

# Configure sentry-native with Unreal's toolchain
cmake -B "build" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DSENTRY_BACKEND=crashpad \
	-DSENTRY_TRANSPORT=none \
	-DBUILD_SHARED_LIBS=ON \
    -DZLIB_LIBRARY="$UE_TOOLCHAIN_PATH/usr/lib/libz.so" \
    -DZLIB_INCLUDE_DIR="$UE_TOOLCHAIN_PATH/usr/include" \
    -DCURL_LIBRARY="$UE_TOOLCHAIN_PATH/usr/lib/libcurl.so" \
    -DCURL_INCLUDE_DIR="$UE_TOOLCHAIN_PATH/usr/include/curl" \
	-DCMAKE_CXX_STANDARD=17 \
	-DCMAKE_CXX_STANDARD_REQUIRED=ON \
	-DCMAKE_CXX_EXTENSIONS=OFF \
	-DCMAKE_SYSROOT="$UE_TOOLCHAIN_PATH"

#-DCMAKE_TOOLCHAIN_FILE="$UE_TOOLCHAIN_PATH/cmake/UE4Toolchain.cmake"

# Build and install sentry-native
cmake --build build --parallel --config RelWithDebInfo
cmake --install build --prefix install --config Release

#7z a Sentry-Native-Linux "./install/*"