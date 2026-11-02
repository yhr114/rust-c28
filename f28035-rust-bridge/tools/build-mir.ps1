#Requires -Version 5.1
<#
.SYNOPSIS
  通用 MIR 固件构建。取代 142 个 build-mir-*.ps1 中 95% 重复的逻辑。

  标准 case：从 tools/mir-cases.json 读取该 case 的字面参数，复刻 legacy 构建序列。
  非标准 case（custom=true）：直接委托给对应的 legacy build-mir-<key>.ps1，行为不变。
#>
param(
    [Parameter(Mandatory = $true)][string]$Case,
    [string]$Compiler = '',
    [string]$Cargo = '',
    [ValidateSet('softlib')][string]$FloatSupport = 'softlib'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\mir-common.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

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
    Write-Output "[build-mir] case '$Case' is non-standard (custom) -> delegating to legacy $($entry.legacyBuild)"
    & (Join-Path $ToolsDir $entry.legacyBuild) -Compiler $Compiler -Cargo $Cargo -FloatSupport $FloatSupport
    if ($LASTEXITCODE -ne 0) { throw "Legacy build failed for $Case." }
    return
}

Build-StandardFirmware -Case $entry -Compiler $Compiler -Cargo $Cargo -FloatSupport $FloatSupport `
    -ProjectRoot $ProjectRoot -ToolsDir $ToolsDir

