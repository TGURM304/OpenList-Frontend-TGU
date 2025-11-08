# ==========================================
# OpenList Frontend Build Script (PowerShell)
# ==========================================

param(
    [switch]$dev,
    [switch]$release,
    [switch]$compress,
    [switch]$no_compress,
    [switch]$enforce_tag,
    [switch]$skip_i18n,
    [switch]$lite,
    [switch]$help
)

# ==== Color helpers ====
$RED    = "31"
$GREEN  = "32"
$YELLOW = "33"
$BLUE   = "34"
$PURPLE = "35"
$CYAN   = "36"

function Log($msg, $color) { Write-Host $msg -ForegroundColor ([System.ConsoleColor]::FromName($color)) }
function Info($msg) { Log $msg "Cyan" }
function Success($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Error($msg) { Write-Host "✗ Error: $msg" -ForegroundColor Red }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Step($msg) { Write-Host $msg -ForegroundColor Magenta }
function Build($msg) { Write-Host $msg -ForegroundColor Blue }

# ==== Help message ====
if ($help) {
    Write-Host "Usage: ./build.ps1 [--dev|--release] [--compress|--no-compress] [--enforce-tag] [--skip-i18n] [--lite]"
    exit 0
}

# ==== Set defaults ====
$BUILD_TYPE   = if ($dev) {"dev"} elseif ($release) {"release"} else {"dev"}
#$COMPRESS_FLAG = if ($compress) {"true"} elseif ($no_compress) {"false"} else {"false"}
#$ENFORCE_TAG   = if ($enforce_tag) {"true"} else {"false"}
#$SKIP_I18N     = if ($skip_i18n) {"true"} else {"false"}
#$LITE_FLAG     = if ($lite) {"true"} else {"false"}

$ENFORCE_TAG   = if ($enforce_tag) { $true } else { $false }
$SKIP_I18N     = if ($skip_i18n) { $true } else { $false }
$LITE_FLAG     = if ($lite) { $true } else { $false }
$COMPRESS_FLAG = if ($compress) { $true } elseif ($no_compress) { $false } else { $false }


# ==== Git Version ====
try {
    if ($BUILD_TYPE -eq "release" -or $ENFORCE_TAG -eq "true") {
        $git_version = git describe --abbrev=0 --tags
        if (-not $git_version) { throw "No git tags found" }
        $package_version = (Get-Content package.json | Select-String '"version":').ToString() -replace '.*"version": *"([^"]*)".*', '$1'
        $git_version_clean = $git_version.TrimStart('v')
        if ($package_version -ne $git_version_clean) {
            throw "package.json version ($package_version) does not match git tag ($git_version_clean)"
        }
    } else {
        $git_version = git describe --abbrev=0 --tags 2>$null
        if (-not $git_version) { $git_version = "v0.0.0" }
        $git_version_clean = $git_version.TrimStart('v')
    }
    $commit = (git rev-parse --short HEAD).Trim()
} catch {
    Error $_
    exit 1
}

# ==== Update package version ====
if ($BUILD_TYPE -eq "dev") {
    (Get-Content package.json) -replace '"version": *"[^"]*"', "`"version`": `"$git_version_clean`"" | Set-Content package.json
    Success "Package.json version updated to $git_version_clean"
    $version_tag = "v${git_version_clean}-${commit}"
    Build "Building DEV version $version_tag ..."
} else {
    $version_tag = "v${git_version_clean}"
    Build "Building RELEASE version $version_tag ..."
}

# ==== Build steps ====
Step "==== Installing dependencies ===="
pnpm install

Step "==== Building i18n ===="
if ($SKIP_I18N -eq $false) {
    pnpm run i18n:release
} else {
    Warn "Skipping i18n build step (fetch not implemented in PowerShell version)"
}

Step "==== Building project ===="
if ($LITE_FLAG -eq $true) {
    pnpm run build:lite
} else {
    pnpm run build
}

# ==== Write version ====
Step "Writing version $version_tag to dist/VERSION ..."
"$version_tag" | Out-File -Encoding utf8 dist/VERSION
Success "Version file created"

# ==== Compress ====
if ($COMPRESS_FLAG -eq $true) {
    Step "Creating compressed archive..."
    $archiveName = if ($LITE_FLAG -eq "true") {"openlist-frontend-dist-lite-$version_tag"} else {"openlist-frontend-dist-$version_tag"}
    Compress-Archive -Path "dist/*" -DestinationPath "dist/$archiveName.zip" -Force
    Success "Archive created: dist/$archiveName.zip"
}

Success "Build completed successfully."
