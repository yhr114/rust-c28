#Requires -Version 5.1
param(
    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml',
    [string]$Xds100Serial = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }
if (-not $Xds100Serial) { $Xds100Serial = $Toolchain.Xds100Serial }

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$safeRoot = $root
$baseOutDir = Join-Path $root 'build\mir-control-loop'
$outDir = Join-Path $root 'build\mir-control-loop-ram'
$ramOut = Join-Path $outDir 'rust_control_loop_ram.out'
$ramMap = Join-Path $outDir 'rust_control_loop_ram.map'

foreach ($p in @($Compiler, $Dss, $TargetConfig)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build MIR control-loop objects =='
    & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1') -Compiler $Compiler
    if ($LASTEXITCODE -ne 0) { throw 'MIR control-loop object build failed.' }
}

Write-Output '== [2/3] RAM relink control-loop firmware =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objects = @(
    (Join-Path $baseOutDir 'codestart.obj'),
    (Join-Path $baseOutDir 'main.obj'),
    (Join-Path $baseOutDir 'rust_control_loop.obj'),
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
$linkOut = @(& $Compiler @linkArgs 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ramOut)) {
    $linkOut | ForEach-Object { Write-Output $_ }
    throw 'RAM relink failed.'
}

$flashHits = Select-String -Path $ramMap -Pattern '^\s*\.(text|cinit|econst|const)\s+' | ForEach-Object {
    $c = @($_.Line -split '\s+' | Where-Object { $_ -ne '' })
    if ($c.Count -ge 3 -and [Convert]::ToInt64($c[2], 16) -ge 0x3E0000) { $_.Line }
}
if ($flashHits) { throw "RAM link leaked into flash: $($flashHits -join ' | ')" }
Write-Output "RAM link OK: $ramOut"

Write-Output '== [3/3] JTAG RAM verify control loop =='
if (Test-Path -LiteralPath $Xds100Serial) {
    $probe = @(& $Xds100Serial 2>&1 | ForEach-Object { "$_" })
    if (($probe -join "`n") -match 'No XDS100 emulators were found') {
        $probe | ForEach-Object { Write-Output $_ }
        throw 'No XDS100 emulator is currently enumerated; RAM/JTAG verification cannot run.'
    }
}
$verifyJs = Join-Path $PSScriptRoot 'verify-mir-control-loop.js'
$vOut = @(& $Dss $verifyJs $TargetConfig $ramOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
if (($vOut -join "`n") -notmatch 'MIR_CONTROL_LOOP_TARGET_TEST=PASS') {
    throw 'Target verification failed for MIR control loop RAM build.'
}
Write-Output 'RESULT: PASS  control_loop (Safe HAL ADC/PWM/Timer/GPIO, MIR true-compile, RAM verify, flash untouched)'
