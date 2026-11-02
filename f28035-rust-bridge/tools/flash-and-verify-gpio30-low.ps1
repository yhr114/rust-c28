param(
    [string]$Dss = '',
    [string]$TargetConfig,
    [switch]$SkipBuild,
    # 显式覆盖新鲜度门禁：加载可能过期的旧映像（仅在有意识复现旧行为时使用）
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

$firmware = Join-Path $projectRoot 'build\gpio30-low\gpio30_low_test.out'
$verificationScript = Join-Path $PSScriptRoot 'verify-gpio30-low.js'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-gpio30-low.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'GPIO30 firmware build failed.' }
}

# 上板前门禁：映像必须来自当前输入（源码/features/桥/编译器），否则拒绝加载
Assert-ImageFresh -Image $firmware -Key (Get-GpioTargetImageKey -Compiler $Toolchain.Compiler -ProjectRoot $projectRoot -Target gpio30) `
    -Context 'flash-and-verify-gpio30-low' -AllowStale:$Force

foreach ($requiredFile in @($Dss, $TargetConfig, $firmware, $verificationScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}

$dssOutput = @(& $Dss $verificationScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output $_ }

if (-not ($dssOutput -match '^GPIO30_LOW_TARGET_TEST=PASS$')) {
    throw 'On-target GPIO30-low verification did not report PASS.'
}
