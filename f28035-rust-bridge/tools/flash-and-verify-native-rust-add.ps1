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

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-native-rust-add.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Native Rust build failed.' }
}

$firmware = Join-Path $projectRoot 'build\native-rust-add\native_rust_add_test.out'
$verificationScript = Join-Path $PSScriptRoot 'verify-rust-add.js'
$dssOutput = @(& $Dss $verificationScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output $_ }

if (-not ($dssOutput -match '^RUST_ADD_TARGET_TEST=PASS$')) {
    throw 'Native Rust C28x verification did not report PASS.'
}
