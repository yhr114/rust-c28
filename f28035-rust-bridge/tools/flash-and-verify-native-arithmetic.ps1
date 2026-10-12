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
    & (Join-Path $PSScriptRoot 'build-native-arithmetic.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Native arithmetic build failed.' }
}

$firmware = Join-Path $projectRoot 'build\native-arithmetic\native_arithmetic_test.out'
$script = Join-Path $PSScriptRoot 'verify-native-arithmetic.js'
$output = @(& $Dss $script $TargetConfig $firmware 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^NATIVE_ARITHMETIC_TARGET_TEST=PASS$')) {
    throw 'Native arithmetic hardware verification did not report PASS.'
}
