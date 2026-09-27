# Self-elevate the script to run as Administrator (required for Visual Studio installer)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script needs Administrator privileges to install Visual Studio Build Tools." -ForegroundColor Yellow
    Write-Host "Relaunching as Administrator..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

$ErrorActionPreference = "Stop"

# --- Configuration ---
$FLUTTER_VERSION = "3.44.4" # Target stable version matching CI
$INSTALL_DIR = "C:\Development"
$FLUTTER_ZIP_URL = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${FLUTTER_VERSION}-stable.zip"
$VS_BUILDTOOLS_URL = "https://aka.ms/vs/17/release/vs_buildtools.exe"
$scriptDir = $PSScriptRoot
if ($scriptDir -eq "" -or $scriptDir -eq $null) { $scriptDir = Get-Location }

# Resolve the project root containing pubspec.yaml (checks script folder, then parent folder)
$PROJECT_DIR = $scriptDir
if (-not (Test-Path "$PROJECT_DIR\pubspec.yaml") -and (Test-Path "$(Split-Path $PROJECT_DIR -Parent)\pubspec.yaml")) {
    $PROJECT_DIR = Split-Path $PROJECT_DIR -Parent
}

# Ensure installation directory exists
if (-not (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null
}

# Ensure TLS 1.2 is active for .NET web fallback
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Helper function to download files reliably using curl.exe (native on Win 10/11) to avoid Invoke-WebRequest memory buffering/progress-bar hangs
function Download-File {
    param (
        [string]$Url,
        [string]$OutPath
    )
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        Write-Host "Downloading via curl..." -ForegroundColor Cyan
        & curl.exe -L -o $OutPath $Url
    } else {
        Write-Host "Downloading via Invoke-WebRequest (fallback)..." -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutPath
    }
}

# --- 1. Install Git if missing ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "=== Installing Git for Windows ===" -ForegroundColor Green
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe"
    $gitInstaller = "$env:TEMP\git_setup.exe"
    
    Download-File -Url $gitUrl -OutPath $gitInstaller
    
    Write-Host "Installing Git (silent)..." -ForegroundColor Cyan
    Start-Process -FilePath $gitInstaller -ArgumentList "/SILENT /NORESTART /NOCANCEL /SP-" -Wait -NoNewWindow
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "Git installed successfully." -ForegroundColor Gray
} else {
    Write-Host "Git is already installed." -ForegroundColor Gray
}

# --- 2. Install Visual Studio C++ Build Tools ---
Write-Host "=== Checking Visual Studio C++ Build Tools ===" -ForegroundColor Green
# We check if MSBuild or vswhere detects the C++ Desktop workload
$vsWherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCppWorkload = $false

if (Test-Path $vsWherePath) {
    $vsInstallations = & $vsWherePath -products * -requires Microsoft.VisualStudio.Workload.VCTools -format json | ConvertFrom-Json
    if ($vsInstallations.Count -gt 0) {
        $hasCppWorkload = $true
    }
}

if (-not $hasCppWorkload) {
    Write-Host "Visual Studio C++ Build Tools not found. Installing..." -ForegroundColor Cyan
    $vsInstaller = "$env:TEMP\vs_buildtools.exe"
    
    Download-File -Url $VS_BUILDTOOLS_URL -OutPath $vsInstaller
    
    Write-Host "Installing C++ Build Tools (this may take 10-15 minutes)..." -ForegroundColor Cyan
    # Install VCTools (C++ Build Tools workload) and recommended packages
    $arguments = @(
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended",
        "--passive",
        "--norestart",
        "--wait"
    )
    Start-Process -FilePath $vsInstaller -ArgumentList $arguments -Wait -NoNewWindow
    Write-Host "Visual Studio Build Tools installed." -ForegroundColor Gray
} else {
    Write-Host "Visual Studio C++ Build Tools are already installed." -ForegroundColor Gray
}

# --- 3. Install/Configure Flutter SDK ---
Write-Host "=== Setting up Flutter SDK ===" -ForegroundColor Green
$flutterPath = "$INSTALL_DIR\flutter\bin"

$versionFile = "$INSTALL_DIR\flutter\version"
$needsDownload = $true
if (Test-Path "$INSTALL_DIR\flutter\bin\flutter.bat") {
    $needsDownload = $false
    if (Test-Path $versionFile) {
        $existingVersion = (Get-Content $versionFile -Raw).Trim()
        Write-Host "Flutter SDK v$existingVersion is already installed at $INSTALL_DIR\flutter." -ForegroundColor Gray
    } else {
        Write-Host "Flutter SDK is already installed at $INSTALL_DIR\flutter." -ForegroundColor Gray
    }
}

if ($needsDownload) {
    $flutterZip = "$env:TEMP\flutter.zip"
    Write-Host "Downloading Flutter SDK v${FLUTTER_VERSION}..." -ForegroundColor Cyan
    Download-File -Url $FLUTTER_ZIP_URL -OutPath $flutterZip
    
    Write-Host "Extracting Flutter SDK to $INSTALL_DIR..." -ForegroundColor Cyan
    Expand-Archive -Path $flutterZip -DestinationPath $INSTALL_DIR
    Remove-Item $flutterZip
}

# Add Flutter to the current process PATH
$env:Path = "$flutterPath;$env:Path"

# Check if Flutter path is in User PATH permanently
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*flutter\bin*") {
    Write-Host "Adding Flutter to User PATH environment variable..." -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$INSTALL_DIR\flutter\bin", "User")
}

# Accept licenses & configure desktop
& flutter config --enable-windows-desktop | Out-Null

# --- 4. Run Build Setup ---
Write-Host "=== Building Application ===" -ForegroundColor Green
Set-Location $PROJECT_DIR

Write-Host "Getting Pub Packages..." -ForegroundColor Cyan
& flutter pub get

Write-Host "Running code generation (build_runner)..." -ForegroundColor Cyan
& dart run build_runner build --delete-conflicting-outputs

Write-Host "Building Windows Release (cross-compiling to x64)..." -ForegroundColor Cyan
& flutter build windows --release

# --- 5. Packaging ---
Write-Host "=== Packaging Build ===" -ForegroundColor Green
$releaseDir = "$PROJECT_DIR\build\windows\x64\runner\Release"
$zipFile = "$PROJECT_DIR\pinbench_windows.zip"

if (Test-Path $zipFile) {
    Remove-Item $zipFile
}

if (Test-Path $releaseDir) {
    Write-Host "Compressing release folder to $zipFile..." -ForegroundColor Cyan
    Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipFile
    
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "SUCCESS! Your zip package is ready at:" -ForegroundColor Green
    Write-Host $zipFile -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Green
} else {
    Set-Location $PROJECT_DIR
    Write-Error "Build completed, but release directory was not found at $releaseDir"
}

Read-Host "Press Enter to exit"
