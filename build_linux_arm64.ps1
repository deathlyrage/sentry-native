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

# Verify toolchain has required files
$GccPath = Join-Path $ToolchainPath "bin\$ArchTriplet-gcc.exe"
if (-not (Test-Path $GccPath)) {
    Write-Host "ERROR: GCC not found at: $GccPath" -ForegroundColor Red
    Write-Host "Please verify the toolchain path is correct." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Sentry Native - Linux ARM64 Build" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Toolchain:   $ToolchainPath" -ForegroundColor White
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

# Check Ninja
try {
    $ninjaVersion = & ninja --version 2>&1
    Write-Host "  [OK] Ninja: version $ninjaVersion" -ForegroundColor Green
    $Generator = "Ninja"
}
catch {
    Write-Host "  [WARNING] Ninja not found, falling back to NMake" -ForegroundColor Yellow
    $Generator = "NMake Makefiles"
}

Write-Host ""

# ============================================================================
# Configure CMake
# ============================================================================

Write-Host "Configuring CMake..." -ForegroundColor Yellow

$CMakeArgs = @(
    "-B", "build"
    "-G", $Generator
    "-DCMAKE_BUILD_TYPE=$BuildType"
    "-DCMAKE_INSTALL_PREFIX=$PWD\install"
    "-DSENTRY_BACKEND=crashpad"
    "-DSENTRY_TRANSPORT=none"
    "-DBUILD_SHARED_LIBS=ON"
    "-DSENTRY_BUILD_TESTS=OFF"
    "-DSENTRY_BUILD_EXAMPLES=OFF"
    "-DCMAKE_C_COMPILER=$ToolchainPath\bin\$ArchTriplet-gcc.exe"
    "-DCMAKE_CXX_COMPILER=$ToolchainPath\bin\$ArchTriplet-g++.exe"
    "-DCMAKE_AR=$ToolchainPath\bin\$ArchTriplet-ar.exe"
    "-DCMAKE_RANLIB=$ToolchainPath\bin\$ArchTriplet-ranlib.exe"
    "-DCMAKE_STRIP=$ToolchainPath\bin\$ArchTriplet-strip.exe"
    "-DCMAKE_SYSTEM_NAME=Linux"
    "-DCMAKE_SYSTEM_PROCESSOR=$Arch"
    "-DCMAKE_SYSROOT=$ToolchainPath"
    "-DCMAKE_FIND_ROOT_PATH=$ToolchainPath"
    "-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    "-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
    "-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
    "-DCMAKE_CXX_STANDARD=17"
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
    "-DCMAKE_CXX_EXTENSIONS=OFF"
)

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