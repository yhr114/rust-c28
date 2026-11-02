#Requires -Version 5.1
# c28x-pac 校准位图的 B-1 真机验证：构建（RAM）+ dss JTAG 校验，一条龙。
# 用法：
#   .\tools\verify-bare-pac-hwtest-ram.ps1                 # 构建 + 上板
#   .\tools\verify-bare-pac-hwtest-ram.ps1 -SkipBuild      # 复用现有映像（过门禁）
#   .\tools\verify-bare-pac-hwtest-ram.ps1 -SkipBuild -Force  # 显式放行旧映像
param(
    [string]$Dss = '',
    [string]$TargetConfig = '',
    [switch]$SkipBuild,
    [switch]$Force,
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
if (-not $TargetConfig) {
    $TargetConfig = Join-Path (Split-Path -Parent $PSScriptRoot) 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$firmware = Join-Path $root 'build\bare-pac-hwtest\pac_hwtest_ram.out'
$verifyScript = Join-Path $PSScriptRoot 'verify-bare-pac-hwtest-ram.js'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-bare-pac-hwtest-ram.ps1') -Compiler $Compiler -Cargo $Cargo
    if ($LASTEXITCODE -ne 0) { throw 'PAC hwtest build failed.' }
}
else {
    # 与构建脚本相同的 key 做上板前门禁
    $Compiler2 = if ($Compiler) { $Compiler } else { $Toolchain.Compiler }
    Assert-ImageFresh -Image $firmware -Key (New-ImageKey -Label 'bare-pac-hwtest' `
        -Tags @{ entry = 'rust_pac_hwtest'; float = 'softlib' } `
        -Files @((Join-Path $root 'crates\bare-pac-hwtest\src\lib.rs'),
            (Join-Path $root 'platform\runtime\pac_hwtest_ram_start.asm'),
            (Join-Path $PSScriptRoot 'F28035_ram.cmd'),
            (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')) `
        -Compiler $Compiler2) -Context 'verify-bare-pac-hwtest-ram' -AllowStale:$Force
}

foreach ($requiredFile in @($Dss, $TargetConfig, $firmware, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) { throw "Required file not found: $requiredFile" }
}

$dssOutput = @(& $Dss $verifyScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output "$_" }

if (-not ($dssOutput -match '^PAC_HWTEST=PASS$')) {
    throw 'On-target PAC/HAL hardware verification did not report PASS.'
}
