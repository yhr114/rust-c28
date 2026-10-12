param(
    [string]$Dss = '',
    [string]$TargetConfig
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }

# Mass-erase the CSM on a secured F28035. Wipes all flash; reflash afterwards.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\targetConfigs\TMS320F28035.ccxml'
}
$script = Join-Path $PSScriptRoot 'unlock-csm-mass-erase.js'
foreach ($requiredFile in @($Dss, $TargetConfig, $script)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}

Write-Host "WARNING: this will ERASE all flash on the F28035 and clear the CSM."
$output = @(& $Dss $script $TargetConfig 2>&1)
$output | ForEach-Object { Write-Output $_ }
if (-not ($output -match '^CSM_MASS_ERASE_UNLOCK=PASS$')) {
    throw 'CSM mass erase did not report PASS. Read the ERROR/FAIL lines above.'
}
Write-Host "Unlocked. Reflash with: .\tools\build-mir-control-loop.ps1 then .\tools\flash-and-verify-mir-control-loop.ps1 -SkipBuild"
