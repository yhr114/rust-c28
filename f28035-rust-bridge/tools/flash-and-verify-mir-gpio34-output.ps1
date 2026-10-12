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
    & (Join-Path $PSScriptRoot 'build-mir-gpio34-output.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'GPIO34 persistent Flash build failed.' }
}

$firmware = Join-Path $projectRoot 'build\mir-gpio34-output\gpio34_output_mir.out'
$programScript = Join-Path $PSScriptRoot 'verify-gpio34-output.js'
$persistentScript = Join-Path $PSScriptRoot 'verify-gpio34-persistent.js'
foreach ($required in @($Dss, $TargetConfig, $firmware, $programScript, $persistentScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required Flash input not found: $required"
    }
}

Write-Output 'Programming audited GPIO34 image with CCS Flash operations: Erase, Program, Verify.'
$programOutput = @(& $Dss $programScript $TargetConfig $firmware 2>&1)
$programOutput | ForEach-Object { Write-Output $_ }
if (-not ($programOutput -match '^FLASH_LOAD_PROGRAM=PASS$')) {
    throw 'CCS Flash loader did not complete Erase, Program, Verify.'
}
if (-not ($programOutput -match '^GPIO34_OUTPUT_TARGET_TEST=PASS$')) {
    throw 'GPIO34 immediate post-program verification failed.'
}

Write-Output 'Resetting through Boot ROM and verifying the already-programmed image without another Flash load.'
$persistentOutput = @(& $Dss $persistentScript $TargetConfig $firmware 2>&1)
$persistentOutput | ForEach-Object { Write-Output $_ }
if (-not ($persistentOutput -match '^GPIO34_PERSISTENT_BOOT_TEST=PASS$')) {
    throw 'Flash was programmed, but reset did not boot the persistent GPIO34 image.'
}

Write-Output 'GPIO34_FLASH_PERSISTENCE=PASS'
Write-Output 'For a true power-loss check: remove power, restore power, then run tools\verify-gpio34-persistent.ps1.'
