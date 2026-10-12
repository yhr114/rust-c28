param(
    [string]$Dss = '',
    [string]$TargetConfig,
    [switch]$SkipBuild
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $TargetConfig) {
    $TargetConfig = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\targetConfigs\TMS320F28035.ccxml'
}

$firmware = Join-Path $projectRoot 'build\rust-add\rust_add_test.out'
$verificationScript = Join-Path $PSScriptRoot 'verify-rust-add.js'

foreach ($requiredFile in @($Dss, $TargetConfig, $verificationScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-rust-add.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "Rust add build failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $firmware)) {
    throw "Firmware not found: $firmware"
}

Write-Output "Programming and running $firmware"
Write-Output "Target configuration: $TargetConfig"
$dssOutput = @(& $Dss $verificationScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output $_ }

if (-not ($dssOutput -match '^RUST_ADD_TARGET_TEST=PASS$')) {
    throw 'On-target rust_add verification did not report PASS.'
}
