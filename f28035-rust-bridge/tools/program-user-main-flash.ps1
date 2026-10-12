#Requires -Version 5.1
param(
    [switch]$ConfirmFlashErase,
    [string]$Compiler = '',
    [string]$Cargo = '',
    [string]$Dss = '',
    [string]$TargetConfig = '',
    [string]$BackupFile = ''
)

if (-not $ConfirmFlashErase) {
    throw 'Flash programming erases sector A. Re-run with -ConfirmFlashErase after reviewing the backup and boot-mode requirements.'
}
. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
foreach ($path in @($Dss, $TargetConfig)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Flash input: $path" }
}

$buildArgs = @{}
if ($Compiler) { $buildArgs['Compiler'] = $Compiler }
if ($Cargo) { $buildArgs['Cargo'] = $Cargo }
$build = @(& (Join-Path $PSScriptRoot 'build-user-main-flash.ps1') @buildArgs 2>&1 | ForEach-Object { "$_" })
$build | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($build -join "`n") -notmatch 'FLASH_BUILD_ONLY=PASS') {
    throw 'Flash build or image audit failed.'
}
$out = Join-Path $root 'build\user-main-flash\user_main_flash.out'
if (-not (Test-Path -LiteralPath $out -PathType Leaf)) { throw "Missing audited Flash image: $out" }

if (-not $BackupFile) {
    $backupRoot = Join-Path $root 'backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $BackupFile = Join-Path $backupRoot ('user-flash-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bin')
}
$BackupFile = [System.IO.Path]::GetFullPath($BackupFile)
if (Test-Path -LiteralPath $BackupFile) { throw "Refusing to overwrite Flash backup: $BackupFile" }
$backupDirectory = Split-Path -Parent $BackupFile
if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
    throw "Backup directory does not exist: $backupDirectory"
}

Write-Output "Backing up all user Flash before sector-A erase: $BackupFile"
$backup = @(& $Dss (Join-Path $PSScriptRoot 'backup-user-flash.js') $TargetConfig $BackupFile 2>&1 | ForEach-Object { "$_" })
$backup | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($backup -join "`n") -notmatch 'BACKUP_OK=' -or
    -not (Test-Path -LiteralPath $BackupFile -PathType Leaf) -or
    (Get-Item -LiteralPath $BackupFile).Length -lt 131072) {
    throw 'Flash backup failed; programming was not attempted.'
}

$program = @(& $Dss (Join-Path $PSScriptRoot 'program-user-main-flash.js') $TargetConfig $out 2>&1 | ForEach-Object { "$_" })
$program | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($program -join "`n") -notmatch 'USER_MAIN_FLASH_PROGRAM=PASS') {
    throw "Flash programming failed. Backup remains at $BackupFile"
}

$verify = @(& (Join-Path $PSScriptRoot 'verify-user-main-flash.ps1') -Dss $Dss -TargetConfig $TargetConfig 2>&1 | ForEach-Object { "$_" })
$verify | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($verify -join "`n") -notmatch 'USER_MAIN_FLASH_BOOT=PASS') {
    throw 'Flash programmed, but reset-boot verification failed.'
}
Write-Output "FLASH_BACKUP=$BackupFile"
Write-Output 'USER_MAIN_FLASH_PERSISTENCE=PASS'
