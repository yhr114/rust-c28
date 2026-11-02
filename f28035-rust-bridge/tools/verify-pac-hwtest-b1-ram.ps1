#Requires -Version 5.1
# c28x-pac 校准位图的 B-1 真机验证一条龙：bundle rustc 构建（RAM）+ dss 校验。
# 探针依赖真身 c28x-pac crate（LLVM 后端路径），覆盖 GPIO/Timer0 TIF/SCI/SPI
# 四组校准行为。用法：
#   .\tools\verify-pac-hwtest-b1-ram.ps1                # 构建 + 上板
#   .\tools\verify-pac-hwtest-b1-ram.ps1 -SkipBuild     # 复用现有映像（过门禁）
#   .\tools\verify-pac-hwtest-b1-ram.ps1 -SkipBuild -Force
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
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'f28035-rust-bridge-b1') 'tools\toolchain-release.ps1')

if (-not $Dss) { $Dss = $Toolchain.Dss }
if (-not $TargetConfig) {
    $TargetConfig = Join-Path (Split-Path -Parent $PSScriptRoot) 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$firmware = Join-Path $root 'build\pac-hwtest-b1\pac_hwtest_ram.out'
$verifyScript = Join-Path $PSScriptRoot 'verify-bare-pac-hwtest-ram.js'
$BundleRustc = (Get-C28xBundle).Rustc

if ($SkipBuild) {
    Assert-ImageFresh -Image $firmware -Key (New-ImageKey -Label 'pac-hwtest-b1' `
        -Tags @{ entry = 'rust_pac_hwtest'; float = 'softlib' } `
        -Files @((Join-Path $root 'crates\pac-hwtest-b1\src\lib.rs'),
            (Join-Path $root 'crates\pac-hwtest-b1\Cargo.toml'),
            (Join-Path $root 'crates\c28x-pac\src\lib.rs'),
            (Join-Path $root 'crates\c28x-pac\Cargo.toml'),
            (Join-Path $root 'platform\runtime\pac_hwtest_ram_start.asm'),
            (Join-Path $root 'platform\runtime\pac_hwtest_eallow.asm'),
            (Join-Path $PSScriptRoot 'F28035_ram.cmd'),
            (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')) `
        -Compiler $BundleRustc) -Context 'verify-pac-hwtest-b1-ram' -AllowStale:$Force
}
else {
    & (Join-Path $PSScriptRoot 'build-pac-hwtest-b1-ram.ps1') -Compiler $Compiler -Cargo $Cargo
    if ($LASTEXITCODE -ne 0) { throw 'PAC hwtest B-1 build failed.' }
}

foreach ($requiredFile in @($Dss, $TargetConfig, $firmware, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) { throw "Required file not found: $requiredFile" }
}

$dssOutput = @(& $Dss $verifyScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output "$_" }

if (-not ($dssOutput -match '^PAC_HWTEST=PASS$')) {
    throw 'On-target PAC/HAL hardware verification did not report PASS.'
}
