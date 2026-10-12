#Requires -Version 5.1
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
$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root 'build\mir-adc_eoc_irq'
$RamOut = Join-Path $OutDir 'adc_eoc_irq_ram.out'
$RamMap = Join-Path $OutDir 'adc_eoc_irq_ram.map'

if (-not $SkipBuild) {
    Write-Output '== [1/3] Build =='
    & (Join-Path $PSScriptRoot 'build-mir-adc-eoc-irq.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
}

Write-Output '== [2/3] RAM relink =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objects = @(
    (Join-Path $OutDir 'codestart.obj'),
    (Join-Path $OutDir 'adc_eoc_irq_switch_test.obj'),
    (Join-Path $OutDir 'rust_adc_eoc_irq.obj'),
    (Join-Path $Root 'build\c28x\f28035_bridge.obj'),
    (Join-Path $OutDir 'sysctrl.obj'),
    (Join-Path $OutDir 'gpio.obj'),
    (Join-Path $OutDir 'delay.obj')
)
foreach ($o in $objects) { if (-not (Test-Path -LiteralPath $o)) { throw "Missing: $o" } }
Remove-Item $RamOut, $RamMap -ErrorAction SilentlyContinue
& $Compiler @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$RamMap", "--output_file=$RamOut"
) $objects @(
    (Join-Path $Root 'tools\F28035_ram.cmd'),
    (Join-Path $Root 'tools\F28035_EABI_sections_ram.cmd'),
    (Join-Path $PSScriptRoot 'F28035_ramfuncs_zero.cmd'),
    (Join-Path $Root 'platform\firmware\F28035_Peripheral_symbols.cmd'),
    (Join-Path $Root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
    $runtimeLibrary
) 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $RamOut)) { throw 'RAM relink failed.' }
Write-Output "RAM link OK: $RamOut"

Write-Output '== [3/3] JTAG verify =='
$vOut = @(& $Dss (Join-Path $PSScriptRoot 'verify-adc-eoc-irq.js') $TargetConfig $RamOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw "dss exit $LASTEXITCODE" }
if (($vOut -join "`n") -notmatch 'ADC_EOC_IRQ_TARGET_TEST=PASS') { throw 'FAIL' }
Write-Output 'RESULT: PASS  adc_eoc_irq_basic (MIR, RAM verify)'
