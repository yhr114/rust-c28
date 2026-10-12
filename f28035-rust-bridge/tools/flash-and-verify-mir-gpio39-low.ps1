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
    $TargetConfig = Join-Path $projectRoot 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-mir-gpio39-low.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'rustc-MIR GPIO39 firmware build failed.' }
}

$firmware = Join-Path $projectRoot 'build\mir-gpio39-low\gpio39_low_mir.out'
$script = Join-Path $PSScriptRoot 'verify-gpio39-low.js'
foreach ($required in @($Dss, $TargetConfig, $firmware, $script)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required verification input not found: $required"
    }
}

$output = @(& $Dss $script $TargetConfig $firmware 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^GPIO39_LOW_TARGET_TEST=PASS$')) {
    throw 'On-target rustc-MIR GPIO39 verification did not report PASS.'
}
