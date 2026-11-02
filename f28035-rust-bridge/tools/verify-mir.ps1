#Requires -Version 5.1
<#
.SYNOPSIS
  通用 MIR 上板验证（构建 + RAM 重链接 + JTAG 校验）。取代 143 个 verify-mir-*.ps1。

  标准 case：从 tools/mir-cases.json 读取字面参数，复刻 legacy 验证序列。
  非标准 case（custom=true）：直接委托给对应的 legacy verify-mir-<key>.ps1，行为不变。
#>
param(
    [Parameter(Mandatory = $true)][string]$Case,
    [switch]$SkipBuild,
    # 显式覆盖新鲜度门禁：允许加载与当前源码/features/编译器不匹配的旧映像。
    # 仅在确认"我就是想跑旧程序"时使用；默认加载前必须通过 buildstamp 断言。
    [switch]$Force,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\mir-common.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }
$Cargo = $Toolchain.Cargo

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir = $PSScriptRoot
$manifest = Join-Path $ToolsDir 'mir-cases.json'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Manifest not found: $manifest. Run tools/_internal/gen-mir-manifest.py first."
}
$cases = Get-Content $manifest -Raw | ConvertFrom-Json
if (-not $cases.cases.PSObject.Properties[$Case]) {
    throw "Unknown case '$Case'. Available: $($cases.cases.PSObject.Properties.Name -join ', ')"
}
$entry = $cases.cases.$Case

if ($entry.custom) {
    Write-Output "[verify-mir] case '$Case' is non-standard (custom) -> delegating to legacy $($entry.legacyVerify)"
    & (Join-Path $ToolsDir $entry.legacyVerify) -SkipBuild:$SkipBuild -Compiler $Compiler -Dss $Dss -TargetConfig $TargetConfig
    if ($LASTEXITCODE -ne 0) { throw "Legacy verify failed for $Case." }
    return
}

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build MIR firmware =='
    Build-StandardFirmware -Case $entry -Compiler $Compiler -Cargo $Cargo -FloatSupport 'softlib' `
        -ProjectRoot $ProjectRoot -ToolsDir $ToolsDir
}
elseif (-not $Force) {
    Write-Output '== [1/3] Build skipped (-SkipBuild) -> freshness gate will assert before load =='
}
else {
    Write-Warning '== [1/3] Build skipped AND freshness gate overridden (-Force): may load a stale image =='
}
Invoke-StandardRamVerify -Case $entry -Compiler $Compiler -Dss $Dss -TargetConfig $TargetConfig `
    -ProjectRoot $ProjectRoot -ToolsDir $ToolsDir -AllowStale:$Force

