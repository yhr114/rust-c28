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

$firmware = Join-Path $projectRoot 'build\gpio39-low\gpio39_low_test.out'
$verificationScript = Join-Path $PSScriptRoot 'verify-gpio39-low.js'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-gpio39-low.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'GPIO39 firmware build failed.' }
}

foreach ($requiredFile in @($Dss, $TargetConfig, $firmware, $verificationScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}

$dssOutput = @(& $Dss $verificationScript $TargetConfig $firmware 2>&1)
$dssOutput | ForEach-Object { Write-Output $_ }

if (-not ($dssOutput -match '^GPIO39_LOW_TARGET_TEST=PASS$')) {
    throw 'On-target GPIO39-low verification did not report PASS.'
}
