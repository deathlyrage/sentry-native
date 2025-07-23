#!/bin/bash

rm -rf "build"
rm -rf "install"

# Configure sentry-native with Unreal's toolchain
cmake -B "build" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DSENTRY_BACKEND=crashpad \
	-DSENTRY_TRANSPORT=none \
	-DBUILD_SHARED_LIBS=ON

# Build and install sentry-native
cmake --build build --parallel --config RelWithDebInfo
cmake --install build --prefix install --config Release

7z a Sentry-Native-Linux-Arm64 "./install/*"