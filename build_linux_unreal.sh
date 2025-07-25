#!/bin/bash
set -e

# Accept "x86_64" or "aarch64" as the first argument
ARCH="$1"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <x86_64|aarch64>"
    exit 1
fi

if [ "$ARCH" = "aarch64" ]; then
    ARCH_TRIPLET="aarch64-unknown-linux-gnueabi"
elif [ "$ARCH" = "x86_64" ]; then
    ARCH_TRIPLET="x86_64-unknown-linux-gnu"
else
    echo "Unknown ARCH: $ARCH"
    exit 1
fi


# Toolchain download information
TOOLCHAIN_VER="v25_clang-18.1.0-rockylinux8"
TOOLCHAIN_URL="https://cdn.unrealengine.com/Toolchain_Linux/native-linux-${TOOLCHAIN_VER}.tar.gz"
TOOLCHAIN_ARCHIVE="native-linux-${TOOLCHAIN_VER}.tar.gz"
TOOLCHAIN_DIR="$TOOLCHAIN_VER"

#rm -rf "$TOOLCHAIN_DIR" || true

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "Downloading Unreal Engine Linux Toolchain..."
    wget "$TOOLCHAIN_URL"

    echo "Extracting Toolchain..."
    tar -xzvf "$TOOLCHAIN_ARCHIVE"
    rm "$TOOLCHAIN_ARCHIVE"
fi

UE_TOOLCHAIN_PATH="$PWD/$TOOLCHAIN_DIR/${ARCH_TRIPLET}"

rm -rf "build"
rm -rf "install"

# Set the compilers to use Unreal's versions
export SYSROOT="$UE_TOOLCHAIN_PATH"
export CC="${SYSROOT}/bin/${ARCH_TRIPLET}-gcc"
export CXX="${SYSROOT}/bin/${ARCH_TRIPLET}-g++"
export AR="${SYSROOT}/bin/${ARCH_TRIPLET}-ar"
export RANLIB="${SYSROOT}/bin/${ARCH_TRIPLET}-ranlib"
export STRIP="${SYSROOT}/bin/${ARCH_TRIPLET}-strip"
export PKG_CONFIG="${SYSROOT}/bin/${ARCH_TRIPLET}-pkg-config"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"
export LD="${SYSROOT}/bin/${ARCH_TRIPLET}-ld"
export PATH="${SYSROOT}/bin:$PATH"

# Add sysroot and necessary include paths to CFLAGS and CXXFLAGS
export CFLAGS="--sysroot=${SYSROOT} -I${SYSROOT}/include"
export CXXFLAGS="--sysroot=${SYSROOT} -I${SYSROOT}/include -I${SYSROOT}/include/c++/8.5.0 -I${SYSROOT}/include/c++/8.5.0/${ARCH_TRIPLET}"

# Add sysroot and lib path to LDFLAGS
export LDFLAGS="--sysroot=${SYSROOT} -L${SYSROOT}/lib -L${SYSROOT}/lib64 -L${SYSROOT}/usr/lib -L${SYSROOT}/usr/lib64"

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
./Configure linux-${ARCH} --prefix="$UE_TOOLCHAIN_PATH/usr" no-shared no-shared no-tests no-docs no-docs
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

## Build libpsl version (check https://github.com/rockdaboot/libpsl/releases for latest)
#LIBPSL_VER="0.21.5"
#wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/libpsl-$LIBPSL_VER.tar.gz
#tar xf libpsl-$LIBPSL_VER.tar.gz
#rm libpsl-$LIBPSL_VER.tar.gz
#cd libpsl-$LIBPSL_VER
#
## Configure libpsl properly
#./configure --prefix="$UE_TOOLCHAIN_PATH/usr" \
#    --disable-shared \
#    --enable-static \
#    --disable-tools \
#    --with-libiconv-prefix="$UE_TOOLCHAIN_PATH/usr" \
#    --with-libidn2=no \
#    --with-libicu="$UE_TOOLCHAIN_PATH/usr"
## Build and install the complete library
#make -j$(nproc) install-exec
#cd ..

# Install Curl in Sysroot							
CURL_VER="8.15.0"
wget https://curl.se/download/curl-$CURL_VER.tar.gz
tar xf curl-$CURL_VER.tar.gz
cd curl-$CURL_VER
unset LD_LIBRARY_PATH
unset PKG_CONFIG_PATH
./configure \
  --host=${ARCH_TRIPLET} \
  --build=$(gcc -dumpmachine) \
  --prefix=$SYSROOT/usr \
  --with-ssl \
  --without-libpsl \
  --disable-ldap \
  --disable-rtsp \
  --disable-manual \
  --disable-shared \
  --enable-static
make -j$(nproc)
make install

if [ $? -ne 0 ]; then
    echo "curl build failed, exiting."
    exit 1
fi

cd ..

# Configure sentry-native with Unreal's toolchain
cmake -B build \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DSENTRY_BACKEND=crashpad \
    -DSENTRY_TRANSPORT=none \
    -DBUILD_SHARED_LIBS=ON \
    -DZLIB_LIBRARY="$UE_TOOLCHAIN_PATH/usr/lib/libz.so" \
    -DZLIB_INCLUDE_DIR="$UE_TOOLCHAIN_PATH/usr/include" \
	-DCMAKE_PREFIX_PATH="$UE_TOOLCHAIN_PATH/usr" \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DCMAKE_CXX_EXTENSIONS=OFF \
    -DCMAKE_SYSROOT="$UE_TOOLCHAIN_PATH" \
	-DCMAKE_C_COMPILER="$UE_TOOLCHAIN_PATH/bin/${ARCH_TRIPLET}-gcc" \
	-DCMAKE_CXX_COMPILER="$UE_TOOLCHAIN_PATH/bin/${ARCH_TRIPLET}-g++" \
    -DCMAKE_FIND_ROOT_PATH="$UE_TOOLCHAIN_PATH" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
	-DSENTRY_BUILD_TESTS=OFF \
	-DSENTRY_BUILD_EXAMPLES=OFF \
	-G Ninja
	
# Build and install sentry-native
cmake --build build --parallel --config RelWithDebInfo
cmake --install build --prefix install --config Release

7z a Sentry-Native-Linux "./install/*"