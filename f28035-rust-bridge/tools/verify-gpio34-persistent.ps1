param(
    [string]$Dss = '',
    [string]$TargetConfig
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $projectRoot 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}

$firmware = Join-Path $projectRoot 'build\mir-gpio34-output\gpio34_output_mir.out'
$script = Join-Path $PSScriptRoot 'verify-gpio34-persistent.js'
foreach ($required in @($Dss, $TargetConfig, $firmware, $script)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required persistent-boot verification input not found: $required"
    }
}

Write-Output 'This verification loads symbols only; it does not erase or program Flash.'
$output = @(& $Dss $script $TargetConfig $firmware 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^GPIO34_PERSISTENT_BOOT_TEST=PASS$')) {
    throw 'GPIO34 did not boot from the already-programmed Flash image.'
}
