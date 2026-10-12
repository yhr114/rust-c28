#Requires -Version 5.1
param(
    [string]$Dss = '',
    [string]$TargetConfig = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
$out = Join-Path $root 'build\user-main-flash\user_main_flash.out'
foreach ($path in @($Dss, $TargetConfig, $out)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing verification input: $path" }
}
$result = @(& $Dss (Join-Path $PSScriptRoot 'verify-user-main-persistent.js') $TargetConfig $out 2>&1 | ForEach-Object { "$_" })
$result | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -notmatch 'USER_MAIN_FLASH_BOOT=PASS') {
    throw 'Flash reset-boot verification failed. No Flash programming was attempted by this command.'
}
