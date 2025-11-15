# Sentry Native - Linux ARM64 Cross-Compile Script for Windows
# Uses Unreal Engine's cross-compile toolchain (must be already installed)

#Requires -Version 5.1

param(
    [string]$ToolchainPath = "",
    [string]$BuildType = "RelWithDebInfo",
    [switch]$Clean = $false,
    [switch]$SkipBuild = $false
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"

# Architecture settings
$ArchTriplet = "aarch64-unknown-linux-gnueabi"
$Arch = "aarch64"

# If toolchain path not provided, try to auto-detect from environment
if ([string]::IsNullOrEmpty($ToolchainPath)) {
    # Check common environment variables
    if ($env:LINUX_MULTIARCH_ROOT) {
        $ToolchainPath = Join-Path $env:LINUX_MULTIARCH_ROOT $ArchTriplet
        Write-Host "Found toolchain via LINUX_MULTIARCH_ROOT: $ToolchainPath" -ForegroundColor Green
    }
    elseif ($env:UE_TOOLCHAIN_ROOT) {
        $ToolchainPath = Join-Path $env:UE_TOOLCHAIN_ROOT $ArchTriplet
        Write-Host "Found toolchain via UE_TOOLCHAIN_ROOT: $ToolchainPath" -ForegroundColor Green
    }
    else {
        # Try to find it in common locations
        $CommonPaths = @(
            "C:\UnrealToolchains\*\$ArchTriplet",
            "$env:ProgramFiles\Epic Games\Shared\UnrealToolchains\*\$ArchTriplet",
            ".\*\$ArchTriplet"
        )
        
        foreach ($pattern in $CommonPaths) {
            $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $ToolchainPath = $found.FullName
                Write-Host "Auto-detected toolchain at: $ToolchainPath" -ForegroundColor Green
                break
            }
        }
    }
}

# Validate toolchain path
if ([string]::IsNullOrEmpty($ToolchainPath)) {
    Write-Host "ERROR: Toolchain path not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please specify the toolchain path using one of these methods:" -ForegroundColor Yellow
    Write-Host "  1. Pass it as parameter: -ToolchainPath 'C:\Path\To\Toolchain\aarch64-unknown-linux-gnueabi'" -ForegroundColor Yellow
    Write-Host "  2. Set environment variable LINUX_MULTIARCH_ROOT or UE_TOOLCHAIN_ROOT" -ForegroundColor Yellow
    Write-Host "  3. Place toolchain in current directory" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $ToolchainPath)) {
    Write-Host "ERROR: Toolchain path does not exist: $ToolchainPath" -ForegroundColor Red
    exit 1
}

# Normalize path (convert to Unix-style for CMake)
$ToolchainPath = $ToolchainPath.TrimEnd('\')

# Check for both .exe and non-.exe versions of compilers
$CompilerChecks = @(
    @{Path="$ToolchainPath\bin\$ArchTriplet-gcc.exe"; Type="gcc"; Ext=".exe"},
    @{Path="$ToolchainPath\bin\$ArchTriplet-gcc"; Type="gcc"; Ext=""},
    @{Path="$ToolchainPath\bin\clang.exe"; Type="clang"; Ext=".exe"},
    @{Path="$ToolchainPath\bin\clang"; Type="clang"; Ext=""}
)

$CompilerFound = $false
$CompilerType = ""
$CompilerExt = ""

foreach ($check in $CompilerChecks) {
    if (Test-Path $check.Path) {
        $CompilerFound = $true
        $CompilerType = $check.Type
        $CompilerExt = $check.Ext
        Write-Host "Found compiler: $($check.Path)" -ForegroundColor Green
        break
    }
}

if (-not $CompilerFound) {
    Write-Host "ERROR: No compiler found in toolchain!" -ForegroundColor Red
    Write-Host "Checked paths:" -ForegroundColor Yellow
    $CompilerChecks | ForEach-Object { Write-Host "  $($_.Path)" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Listing actual files in bin directory:" -ForegroundColor Yellow
    if (Test-Path "$ToolchainPath\bin") {
        Get-ChildItem "$ToolchainPath\bin" | Select-Object -First 20 | ForEach-Object { 
            Write-Host "  $($_.Name)" -ForegroundColor Gray 
        }
    }
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Sentry Native - Linux ARM64 Build" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Toolchain:   $ToolchainPath" -ForegroundColor White
Write-Host "Compiler:    $CompilerType" -ForegroundColor White
Write-Host "Build Type:  $BuildType" -ForegroundColor White
Write-Host "Target:      Linux ARM64 ($Arch)" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Clean Previous Build
# ============================================================================

if ($Clean -or -not $SkipBuild) {
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    
    if (Test-Path "build") {
        Remove-Item -Recurse -Force "build"
    }
    if (Test-Path "install") {
        Remove-Item -Recurse -Force "install"
    }
    
    Write-Host "Clean complete." -ForegroundColor Green
    Write-Host ""
}

# ============================================================================
# Check Prerequisites
# ============================================================================

Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check CMake
try {
    $cmakeVersion = & cmake --version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] CMake: $cmakeVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] CMake not found in PATH" -ForegroundColor Red
    exit 1
}

# Check for build system
$Generator = $null

# Try Ninja first (recommended)
try {
    $ninjaVersion = & ninja --version 2>&1
    Write-Host "  [OK] Ninja: version $ninjaVersion" -ForegroundColor Green
    $Generator = "Ninja"
}
catch {
    Write-Host "  [INFO] Ninja not found" -ForegroundColor Gray
}

# Try NMake (requires Visual Studio)
if (-not $Generator) {
    try {
        $nmakeVersion = & nmake /? 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -or $nmakeVersion -match "Microsoft") {
            Write-Host "  [OK] NMake found" -ForegroundColor Green
            $Generator = "NMake Makefiles"
        }
    }
    catch {
        Write-Host "  [INFO] NMake not found" -ForegroundColor Gray
    }
}

# Fall back to Unix Makefiles (using toolchain's make)
if (-not $Generator) {
    Write-Host "  [WARNING] Neither Ninja nor NMake found" -ForegroundColor Yellow
    Write-Host "  [INFO] Using Unix Makefiles with toolchain's make" -ForegroundColor Cyan
    Write-Host "" 
    Write-Host "  TIP: For faster builds, install Ninja:" -ForegroundColor Yellow
    Write-Host "       winget install Ninja-build.Ninja" -ForegroundColor Gray
    Write-Host "       or download from: https://github.com/ninja-build/ninja/releases" -ForegroundColor Gray
    Write-Host ""
    $Generator = "Unix Makefiles"
    $UseToolchainMake = $true
}

Write-Host ""

# ============================================================================
# Create CMake Toolchain File
# ============================================================================

Write-Host "Creating CMake toolchain file..." -ForegroundColor Yellow

$ToolchainFile = "$PWD\cmake_toolchain_temp.cmake"

# Convert Windows path to CMake-friendly format
$CMakeToolchainPath = $ToolchainPath -replace '\\', '/'

# Determine compiler paths based on what we found
if ($CompilerType -eq "gcc") {
    $CCPath = "$CMakeToolchainPath/bin/$ArchTriplet-gcc$CompilerExt"
    $CXXPath = "$CMakeToolchainPath/bin/$ArchTriplet-g++$CompilerExt"
    $ARPath = "$CMakeToolchainPath/bin/$ArchTriplet-ar$CompilerExt"
    $RANLIBPath = "$CMakeToolchainPath/bin/$ArchTriplet-ranlib$CompilerExt"
    $STRIPPath = "$CMakeToolchainPath/bin/$ArchTriplet-strip$CompilerExt"
} else {
    $CCPath = "$CMakeToolchainPath/bin/clang$CompilerExt"
    $CXXPath = "$CMakeToolchainPath/bin/clang++$CompilerExt"
    $ARPath = "$CMakeToolchainPath/bin/llvm-ar$CompilerExt"
    $RANLIBPath = "$CMakeToolchainPath/bin/llvm-ranlib$CompilerExt"
    $STRIPPath = "$CMakeToolchainPath/bin/llvm-strip$CompilerExt"
}

$ToolchainContent = @"
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $Arch)

# Must be set before compiler
set(CMAKE_SYSROOT "$CMakeToolchainPath")

# Set compilers
set(CMAKE_C_COMPILER "$CCPath")
set(CMAKE_CXX_COMPILER "$CXXPath")

# Skip the compiler checks - they will fail for cross-compilation
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Set other tools
set(CMAKE_AR "$ARPath" CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB "$RANLIBPath" CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP "$STRIPPath" CACHE FILEPATH "Strip")

# Set compiler target
set(CMAKE_C_COMPILER_TARGET $ArchTriplet)
set(CMAKE_CXX_COMPILER_TARGET $ArchTriplet)

# Search paths - include all standard library locations
set(CMAKE_FIND_ROOT_PATH "$CMakeToolchainPath" "$CMakeToolchainPath/usr" "$CMakeToolchainPath/$ArchTriplet")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Additional library and include search paths
set(CMAKE_LIBRARY_PATH 
    "$CMakeToolchainPath/lib"
    "$CMakeToolchainPath/lib64"
    "$CMakeToolchainPath/usr/lib"
    "$CMakeToolchainPath/usr/lib64"
    "$CMakeToolchainPath/$ArchTriplet/lib"
    "$CMakeToolchainPath/$ArchTriplet/lib64"
    CACHE STRING "")

set(CMAKE_INCLUDE_PATH
    "$CMakeToolchainPath/include"
    "$CMakeToolchainPath/usr/include"
    "$CMakeToolchainPath/$ArchTriplet/include"
    CACHE STRING "")

# Threads configuration for cross-compilation
set(THREADS_PREFER_PTHREAD_FLAG ON)
set(CMAKE_THREAD_LIBS_INIT "-lpthread")
set(CMAKE_HAVE_THREADS_LIBRARY 1)
set(CMAKE_USE_WIN32_THREADS_INIT 0)
set(CMAKE_USE_PTHREADS_INIT 1)
set(Threads_FOUND TRUE)

# Compiler and linker flags
set(CMAKE_C_FLAGS "--sysroot=$CMakeToolchainPath" CACHE STRING "")
set(CMAKE_CXX_FLAGS "--sysroot=$CMakeToolchainPath" CACHE STRING "")
set(CMAKE_EXE_LINKER_FLAGS "--sysroot=$CMakeToolchainPath -pthread" CACHE STRING "")
set(CMAKE_SHARED_LINKER_FLAGS "--sysroot=$CMakeToolchainPath -pthread" CACHE STRING "")
set(CMAKE_MODULE_LINKER_FLAGS "--sysroot=$CMakeToolchainPath -pthread" CACHE STRING "")
"@

Set-Content -Path $ToolchainFile -Value $ToolchainContent -Encoding UTF8
Write-Host "Toolchain file created at: $ToolchainFile" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Configure CMake
# ============================================================================

Write-Host "Configuring CMake..." -ForegroundColor Yellow

$InstallPath = "$PWD\install" -replace '\\', '/'

$CMakeArgs = @(
    "-B", "build"
    "-G", $Generator
    "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFile"
    "-DCMAKE_BUILD_TYPE=$BuildType"
    "-DCMAKE_INSTALL_PREFIX=$InstallPath"
    "-DSENTRY_BACKEND=crashpad"
    "-DSENTRY_TRANSPORT=none"
    "-DBUILD_SHARED_LIBS=ON"
    "-DSENTRY_BUILD_TESTS=OFF"
    "-DSENTRY_BUILD_EXAMPLES=OFF"
    "-DCMAKE_CXX_STANDARD=17"
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
    "-DCMAKE_CXX_EXTENSIONS=OFF"
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    "-DCRASHPAD_ZLIB_SYSTEM=OFF"
)

# If using Unix Makefiles, we need to set the make program
if ($Generator -eq "Unix Makefiles" -and $UseToolchainMake) {
    $MakePath = "$ToolchainPath\bin"
    $env:PATH = "$MakePath;$env:PATH"
    Write-Host "Added toolchain bin to PATH: $MakePath" -ForegroundColor Cyan
    
    # Explicitly set CMAKE_MAKE_PROGRAM
    $CMakeArgs += "-DCMAKE_MAKE_PROGRAM=$CMakeToolchainPath/bin/make"
}

try {
    & cmake @CMakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code $LASTEXITCODE"
    }
    Write-Host "Configuration complete." -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "ERROR: CMake configuration failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Toolchain file contents:" -ForegroundColor Yellow
    Get-Content $ToolchainFile | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    exit 1
}

if ($SkipBuild) {
    Write-Host "Skipping build (SkipBuild flag set)" -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# Build
# ============================================================================

Write-Host "Building..." -ForegroundColor Yellow

try {
    & cmake --build build --parallel --config $BuildType
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }
    Write-Host "Build complete." -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "ERROR: Build failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ============================================================================
# Install
# ============================================================================

Write-Host "Installing..." -ForegroundColor Yellow

try {
    & cmake --install build --config $BuildType
    if ($LASTEXITCODE -ne 0) {
        throw "Install failed with exit code $LASTEXITCODE"
    }
    Write-Host "Install complete." -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "ERROR: Install failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ============================================================================
# Package (Optional)
# ============================================================================

Write-Host "Packaging..." -ForegroundColor Yellow

$ArchiveName = "Sentry-Native-Linux-Arm64"

# Try to find 7z
$SevenZipPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "${env:ProgramFiles}\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

$SevenZip = $null
foreach ($path in $SevenZipPaths) {
    if (Test-Path $path) {
        $SevenZip = $path
        break
    }
}

if ($SevenZip) {
    try {
        & $SevenZip a "$ArchiveName.7z" ".\install\*"
        Write-Host "Package created: $ArchiveName.7z" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Failed to create archive" -ForegroundColor Yellow
    }
}
else {
    # Try using tar (built into Windows 10+)
    try {
        & tar -czf "$ArchiveName.tar.gz" -C install .
        Write-Host "Package created: $ArchiveName.tar.gz" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Failed to create archive (7-Zip and tar not available)" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================================
# Cleanup temporary files
# ============================================================================

if (Test-Path $ToolchainFile) {
    Remove-Item $ToolchainFile -Force
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "BUILD COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output directory: $PWD\install" -ForegroundColor White
Write-Host ""

# List built files
if (Test-Path "install\bin") {
    Write-Host "Binaries:" -ForegroundColor Yellow
    Get-ChildItem "install\bin" | ForEach-Object { Write-Host "  $_" }
}

if (Test-Path "install\lib") {
    Write-Host "Libraries:" -ForegroundColor Yellow
    Get-ChildItem "install\lib" | ForEach-Object { Write-Host "  $_" }
}

if (Test-Path "install\include") {
    Write-Host "Headers:" -ForegroundColor Yellow
    Get-ChildItem "install\include" | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
Write-Host "These files are built for Linux ARM64 (aarch64) and can be used with Unreal Engine." -ForegroundColor Green