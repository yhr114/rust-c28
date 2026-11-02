param(
    [string]$Dss = '',
    [string]$TargetConfig,
    [switch]$SkipBuild,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\standalone-image-keys.ps1')
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

# 上板前门禁：映像必须来自当前输入，否则拒绝加载（-Force 显式绕过）
Assert-ImageFresh -Image $firmware -Key (Get-NativeArithmeticImageKey -Compiler $Toolchain.Compiler -ProjectRoot $projectRoot) `
    -Context 'flash-and-verify-native-arithmetic' -AllowStale:$Force

$output = @(& $Dss $script $TargetConfig $firmware 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^NATIVE_ARITHMETIC_TARGET_TEST=PASS$')) {
    throw 'Native arithmetic hardware verification did not report PASS.'
}
