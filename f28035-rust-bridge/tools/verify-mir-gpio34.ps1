#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot P1 vertical-template verification for gpio34_output_basic over RAM.

.DESCRIPTION
  Builds the MIR-firmware (true rustc -> c28x-mir -> TI assembler), relinks all
  sections into SARAM (RAM, never touches flash), then drives the XDS100v1 probe
  to run it and judge the GPIOB34 mux/direction/data symbols.

  Steps:
    [1/3] build-mir-gpio34-output.ps1   (host tests + MIR lowering + flash .out)
    [2/3] RAM relink                     (sections -> SARAM, Ramfuncs zero)
    [3/3] dss verify-gpio34-output.js    (load -> run -> read symbols -> PASS/FAIL)

.PARAMETER SkipBuild
  Reuse the previously built objects; only relink + verify.
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

# stderr from cl2000/dss carries normal warnings; do not promote them to
# terminating errors (PS5.1 NativeCommandError trap). Judge by $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$script:Root = Split-Path -Parent $PSScriptRoot          # f28035-rust-bridge
$script:SafeRoot = $script:Root
$script:OutDir = Join-Path $script:Root 'build\mir-gpio34-output'
$script:RamOut = Join-Path $script:OutDir 'gpio34_output_ram.out'
$script:RamMap = Join-Path $script:OutDir 'gpio34_output_ram.map'

foreach ($p in @($Compiler, $Dss, $TargetConfig)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
}

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build MIR firmware =='
    & (Join-Path $PSScriptRoot 'build-mir-gpio34-output.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'MIR firmware build failed.' }
}

Write-Output '== [2/3] RAM relink (all sections -> SARAM, no flash) =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objects = @(
    (Join-Path $script:OutDir 'codestart.obj'),
    (Join-Path $script:OutDir 'gpio34_output_test.obj'),
    (Join-Path $script:OutDir 'rust_gpio34_output.obj'),
    (Join-Path $script:Root 'build\c28x\f28035_bridge.obj'),
    (Join-Path $script:OutDir 'sysctrl.obj'),
    (Join-Path $script:OutDir 'gpio.obj'),
    (Join-Path $script:OutDir 'delay.obj')
)
foreach ($o in $objects) { if (-not (Test-Path -LiteralPath $o)) { throw "Missing object: $o" } }

Remove-Item $script:RamOut, $script:RamMap -ErrorAction SilentlyContinue
$linkArgs = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$script:RamMap", "--output_file=$script:RamOut"
) + $objects + @(
    (Join-Path $script:SafeRoot 'tools\F28035_ram.cmd'),
    (Join-Path $script:SafeRoot 'tools\F28035_EABI_sections_ram.cmd'),
    (Join-Path $PSScriptRoot 'F28035_ramfuncs_zero.cmd'),
    (Join-Path $script:Root 'platform\firmware\F28035_Peripheral_symbols.cmd'),
    (Join-Path $script:Root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
    $runtimeLibrary
)
& $Compiler @linkArgs 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $script:RamOut)) { throw 'RAM relink failed.' }

# Guard: no .text/.cinit may land in flash range.
$flashHits = Select-String -Path $script:RamMap -Pattern '^\s*\.(text|cinit|econst|const)\s+' | ForEach-Object {
    $c = @($_.Line -split '\s+' | Where-Object { $_ -ne '' })
    if ($c.Count -ge 3 -and [Convert]::ToInt64($c[2], 16) -ge 0x3E0000) { $_.Line }
}
if ($flashHits) { throw "RAM link leaked into flash: $($flashHits -join ' | ')" }
Write-Output "RAM link OK: $script:RamOut"

Write-Output '== [3/3] JTAG RAM verify (XDS100v1, flash untouched) =='
$verifyJs = Join-Path $PSScriptRoot 'verify-gpio34-output.js'
$vOut = @(& $Dss $verifyJs $TargetConfig $script:RamOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
# Fail closed: a nonzero dss exit (e.g. JS syntax error before the harness ran)
# must never be reported as PASS even if a PASS string leaked from a partial run.
if ($LASTEXITCODE -ne 0) {
    throw "dss exited $LASTEXITCODE while verifying gpio34_output_basic."
}
if (($vOut -join "`n") -notmatch 'GPIO34_OUTPUT_TARGET_TEST=PASS') {
    throw 'Target verification failed for gpio34_output_basic.'
}
Write-Output 'RESULT: PASS  gpio34_output_basic (MIR true-compile, RAM verify, flash untouched)'
