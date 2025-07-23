@echo on

set SRC_DIR=%~dp0

REM call "C:\Program Files (x86)\Microsoft GDK\Command Prompts\GamingXboxVars.cmd" GamingXboxVS2022 240301

cd /D %SRC_DIR%

rmdir /Q /S "build"
rmdir /Q /S "install"

cmake --version

SET BUILD_TYPE="RelWithDebInfo"

cmake -B build -DCMAKE_BUILD_TYPE=%BUILD_TYPE% -DSENTRY_BACKEND=none -DSENTRY_TRANSPORT=none -DSENTRY_BUILD_TESTS=OFF -DSENTRY_BUILD_EXAMPLES=OFF -A Gaming.Xbox.XboxOne.x64 -DCMAKE_TOOLCHAIN_FILE="./toolchains/xbox/gxdk_toolchain.cmake" -DBUILD_SHARED_LIBS=ON -DCMAKE_SYSTEM_VERSION=10 -DSENTRY_WITH_LIBBACKTRACE=true
cmake --build build --parallel --config %BUILD_TYPE%
cmake --install build --prefix install --config %BUILD_TYPE%

REM "C:\\Program Files\\7-Zip\\7z.exe" a Sentry-Native-XB1 "./install/*"