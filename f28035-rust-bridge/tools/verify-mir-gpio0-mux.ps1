#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot P1 vertical-template verification for gpio_mux_basic over RAM.

.DESCRIPTION
  Builds the MUX MIR firmware (true rustc -> c28x-mir -> TI assembler),
  relinks all sections into SARAM (RAM, never touches flash), then drives the
  XDS100v1 probe to run it and judge the two-phase GPIO0 MUX snapshots.

  The Rust application mirrors (rust_api::application::rust_gpio0_mux_to_epwm1a
  and rust_gpio0_mux_restore_gpio) are plain safe Rust: no unsafe, no direct
  FFI -- GPIO0's MUX field is routed 0 -> 1 (EPWM1A) -> 0 (GPIO) via the typed
  Gpio::set_mux.  c28x-mir emits set_mux calls; on any emitted sequence failure
  the Rust function hangs in a trap loop, the C harness never records
  rust_gpio0_mux_called, and the JS judge reports FAIL.

  Steps:
    [1/3] build-mir-gpio0-mux.ps1 (host tests + MIR lowering + flash .out)
    [2/3] RAM relink                     (sections -> SARAM, Ramfuncs zero)
    [3/3] dss verify-gpio0-mux.js (load -> run -> read symbols -> PASS/FAIL)

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
$script:OutDir = Join-Path $script:Root 'build\mir-gpio0-mux'
$script:RamOut = Join-Path $script:OutDir 'gpio0_mux_ram.out'
$script:RamMap = Join-Path $script:OutDir 'gpio0_mux_ram.map'

foreach ($p in @($Compiler, $Dss, $TargetConfig)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
}

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build MIR firmware =='
    & (Join-Path $PSScriptRoot 'build-mir-gpio0-mux.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'MIR firmware build failed.' }
}

Write-Output '== [2/3] RAM relink (all sections -> SARAM, no flash) =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objects = @(
    (Join-Path $script:OutDir 'codestart.obj'),
    (Join-Path $script:OutDir 'gpio0_mux_switch_test.obj'),
    (Join-Path $script:OutDir 'rust_gpio0_mux.obj'),
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
$verifyJs = Join-Path $PSScriptRoot 'verify-gpio0-mux.js'
$vOut = @(& $Dss $verifyJs $TargetConfig $script:RamOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
# Fail closed: a nonzero dss exit (e.g. JS syntax error before the harness ran)
# must never be reported as PASS even if a PASS string leaked from a partial run.
if ($LASTEXITCODE -ne 0) {
    throw "dss exited $LASTEXITCODE while verifying gpio_mux_basic."
}
if (($vOut -join "`n") -notmatch 'GPIO0_MUX_TARGET_TEST=PASS') {
    throw 'Target verification failed for gpio_mux_basic.'
}
Write-Output 'RESULT: PASS  gpio_mux_basic (MIR true-compile, RAM verify, flash untouched)'
