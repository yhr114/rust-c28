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
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'MIR control-loop build failed.' }
}

$firmware = Join-Path $projectRoot 'build\mir-control-loop\rust_control_loop.out'
$script = Join-Path $PSScriptRoot 'verify-mir-control-loop.js'
foreach ($requiredFile in @($Dss, $TargetConfig, $firmware, $script)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}
$output = @(& $Dss $script $TargetConfig $firmware 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^MIR_CONTROL_LOOP_TARGET_TEST=PASS$')) {
    throw 'On-target MIR control-loop verification did not report PASS.'
}
