#Requires -Version 5.1
param([string]$Compiler = '', [string]$Cargo = '', [string]$Dss = '', [string]$TargetConfig = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}

& (Join-Path $PSScriptRoot 'build-ownership-once-ram.ps1') -Compiler $Compiler -Cargo $Cargo
if ($LASTEXITCODE -ne 0) { throw 'Ownership RAM build failed.' }
$firmware = Join-Path $root 'build\ownership-gpio34\ownership_once_ram.out'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verification = @(& $Dss (Join-Path $PSScriptRoot 'verify-ownership-once-ram.js') `
        $TargetConfig $firmware 2>&1 | ForEach-Object { "$_" })
    $verifyExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}
$verification | ForEach-Object { Write-Output $_ }
if ($verifyExit -ne 0 -or ($verification -join "`n") -notmatch 'RUST_ONCE_METHOD_RAM=PASS' -or
    ($verification -join "`n") -match 'RUST_ONCE_METHOD_RAM=FAIL') {
    throw 'Ownership RAM/JTAG verification failed.'
}
Write-Output 'ZERO_C_OWNERSHIP_RAM_JTAG=PASS'
