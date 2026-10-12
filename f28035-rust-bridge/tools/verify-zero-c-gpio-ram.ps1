#Requires -Version 5.1
param(
    [switch]$SafeHal,
    [string]$Compiler = '',
    [string]$Cargo = '',
    [string]$Dss = '',
    [string]$TargetConfig = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
& (Join-Path $PSScriptRoot 'build-bare-gpio34-ram.ps1') -SafeHal:$SafeHal `
    -Compiler $Compiler -Cargo $Cargo
if ($LASTEXITCODE -ne 0) { throw 'Zero-C GPIO build failed.' }

$firmware = if ($SafeHal) {
    Join-Path $root 'build\safe-gpio34\safe_gpio34_ram.out'
} else {
    Join-Path $root 'build\bare-gpio34\bare_gpio34_ram.out'
}
$mode = if ($SafeHal) { 'single' } else { 'multi' }
$passToken = if ($SafeHal) { 'SAFE_HAL_GPIO34_ZERO_C_RAM=PASS' } else { 'BARE_GPIO_MULTI_RAM=PASS' }
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verification = @(& $Dss (Join-Path $PSScriptRoot 'verify-bare-gpio34-ram.js') `
        $TargetConfig $firmware $mode 2>&1 | ForEach-Object { "$_" })
    $verifyExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}
$verification | ForEach-Object { Write-Output $_ }
if ($verifyExit -ne 0 -or ($verification -join "`n") -notmatch [regex]::Escape($passToken) -or
    ($verification -join "`n") -match 'BARE_GPIO34_RAM=FAIL') {
    throw 'RAM/JTAG verification failed.'
}
Write-Output "ZERO_C_RAM_JTAG=PASS $mode"
