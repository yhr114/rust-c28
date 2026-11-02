#Requires -Version 5.1
param(
    [string]$Dss = '',
    [string]$TargetConfig = '',
    # 显式覆盖新鲜度门禁：加载与当前源码/features/编译器可能不匹配的旧
    # Flash 映像。默认拒绝：buildstamp 不匹配即抛错。
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\user-main-image.ps1')
if (-not $Dss) { $Dss = $Toolchain.Dss }
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
$out = Join-Path $root 'build\user-main-flash\user_main_flash.out'

# 上板前门禁：映像必须由当前输入构建（切 features / 改源码后旧映像会被拒绝，
# 提示先跑 build-user-main-flash.ps1）。-Force 显式绕过。
Assert-ImageFresh -Image $out -Key (Get-UserMainImageKey -Compiler $Toolchain.Compiler -ProjectRoot $root -Variant flash) `
    -Context 'verify-user-main-flash' -AllowStale:$Force

foreach ($path in @($Dss, $TargetConfig, $out)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing verification input: $path" }
}
$result = @(& $Dss (Join-Path $PSScriptRoot 'verify-user-main-persistent.js') $TargetConfig $out 2>&1 | ForEach-Object { "$_" })
$result | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -notmatch 'USER_MAIN_FLASH_BOOT=PASS') {
    throw 'Flash reset-boot verification failed. No Flash programming was attempted by this command.'
}
