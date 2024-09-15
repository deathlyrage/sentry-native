@echo off

rmdir /Q /S "build"
rmdir /Q /S "install"

cmake --version

SET BUILD_TYPE="RelWithDebInfo"

cmake -B build -DCMAKE_BUILD_TYPE=%BUILD_TYPE% -DSENTRY_BACKEND=crashpad -DCMAKE_GENERATOR_PLATFORM=ARM64 -DCMAKE_GENERATOR_PLATFORM=x64 -DBUILD_SHARED_LIBS=ON -DCMAKE_SYSTEM_VERSION=10
cmake --build build --parallel --config %BUILD_TYPE%
cmake --install build --prefix install --config %BUILD_TYPE%

REM "C:\\Program Files\\7-Zip\\7z.exe" a Sentry-Native-Win64 "./install/*"

pause