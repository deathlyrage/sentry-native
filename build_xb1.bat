@echo on

set SRC_DIR=%~dp0

call "C:\Program Files (x86)\Microsoft GDK\Command Prompts\GamingXboxVars.cmd" GamingXboxVS2022 240301

cd /D %SRC_DIR%

rmdir /Q /S "build"
rmdir /Q /S "install"

cmake --version

SET BUILD_TYPE="RelWithDebInfo"

cmake -B build -DCMAKE_BUILD_TYPE=%BUILD_TYPE% -DSENTRY_BACKEND=none -DCMAKE_GENERATOR_PLATFORM=x64 -DBUILD_SHARED_LIBS=ON -DCMAKE_SYSTEM_VERSION=6.3
cmake --build build --parallel --config %BUILD_TYPE%
cmake --install build --prefix install --config %BUILD_TYPE%

REM "C:\\Program Files\\7-Zip\\7z.exe" a Sentry-Native-XB1 "./install/*"