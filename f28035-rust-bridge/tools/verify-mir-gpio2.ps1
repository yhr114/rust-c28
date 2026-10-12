#Requires -Version 5.1
<#
.SYNOPSIS
  Verify the Safe Rust -> MIR backend -> RAM route for GPIO2 low.

.DESCRIPTION
  Reuses build-mir-gpio39-low.ps1 to build the rustc-MIR assembly/object from
  rust-api.  That object contains every supported exported Rust function,
  including rust_gpio2_low.  This script relinks it with a GPIO2-specific C
  harness into RAM and verifies the GPIOA2 mux/direction/data snapshot.
#>
param(
    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$safeRoot = $root
$baseOutDir = Join-Path $root 'build\mir-gpio39-low'
$outDir = Join-Path $root 'build\mir-gpio2-low'
$ramOut = Join-Path $outDir 'gpio2_low_ram.out'
$ramMap = Join-Path $outDir 'gpio2_low_ram.map'

foreach ($p in @($Compiler, $Dss, $TargetConfig)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build reusable MIR GPIO object =='
    & (Join-Path $PSScriptRoot 'build-mir-gpio39-low.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'MIR GPIO object build failed.' }
}

Write-Output '== [2/3] RAM relink GPIO2 harness =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$headers = Join-Path $root 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $root 'platform\vendor\ti\f2803x\common\include'
$harnessObject = Join-Path $outDir 'gpio2_low_test.obj'

& $Compiler `
    --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
    --gen_func_subsections=on --opt_level=2 `
    "--include_path=$compilerInclude" "--include_path=$headers" "--include_path=$common" `
    "--output_file=$harnessObject" (Join-Path $root 'platform\firmware\gpio2_low_test.c') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO2 harness.' }

$objects = @(
    (Join-Path $baseOutDir 'codestart.obj'),
    $harnessObject,
    (Join-Path $baseOutDir 'rust_gpio39_low.obj'),
    (Join-Path $root 'build\c28x\f28035_bridge.obj'),
    (Join-Path $baseOutDir 'sysctrl.obj'),
    (Join-Path $baseOutDir 'gpio.obj'),
    (Join-Path $baseOutDir 'delay.obj')
)
foreach ($o in $objects) { if (-not (Test-Path -LiteralPath $o)) { throw "Missing object: $o" } }

Remove-Item $ramOut, $ramMap -ErrorAction SilentlyContinue
$linkArgs = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$ramMap", "--output_file=$ramOut"
) + $objects + @(
    (Join-Path $safeRoot 'tools\F28035_ram.cmd'),
    (Join-Path $safeRoot 'tools\F28035_EABI_sections_ram.cmd'),
    (Join-Path $PSScriptRoot 'F28035_ramfuncs_zero.cmd'),
    (Join-Path $root 'platform\firmware\F28035_Peripheral_symbols.cmd'),
    (Join-Path $root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
    $runtimeLibrary
)
& $Compiler @linkArgs 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ramOut)) { throw 'RAM relink failed.' }

$flashHits = Select-String -Path $ramMap -Pattern '^\s*\.(text|cinit|econst|const)\s+' | ForEach-Object {
    $c = @($_.Line -split '\s+' | Where-Object { $_ -ne '' })
    if ($c.Count -ge 3 -and [Convert]::ToInt64($c[2], 16) -ge 0x3E0000) { $_.Line }
}
if ($flashHits) { throw "RAM link leaked into flash: $($flashHits -join ' | ')" }
Write-Output "RAM link OK: $ramOut"

Write-Output '== [3/3] JTAG RAM verify GPIO2 =='
$verifyJs = Join-Path $PSScriptRoot 'verify-gpio2-low.js'
$vOut = @(& $Dss $verifyJs $TargetConfig $ramOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
if (($vOut -join "`n") -notmatch 'GPIO2_LOW_TARGET_TEST=PASS') {
    throw 'Target verification failed for gpio2_low.'
}
Write-Output 'RESULT: PASS  gpio2_low (Safe HAL, MIR true-compile, RAM verify, flash untouched)'
