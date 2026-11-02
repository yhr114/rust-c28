#Requires -Version 5.1
# Build + verify the Safe HAL GPIO34 image on the DIRECT-OBJECT (LLVM) path.
#
# Pipeline: active B-1 bundle rustc compiles sdk/f28035-safe-hal with the
# `bare-mmio` + `direct-obj-mmio` features to a C28x .obj, cl2000 assembles the
# RAM startup shell and the leaf support (EALLOW/EDIS + saved-INTM critical
# section), links the RAM image, and DSS reads back GPIO34 on real hardware.
#
# The `single` DSS mode checks only GPIO34 (this image drives one pin); the
# default `multi` mode also expects GPIO2 and does not apply here.
param(
    [string]$BundleRoot = '',
    [string]$Compiler = '',
    [switch]$BuildOnly,
    [switch]$Exclusive
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $BundleRoot) {
    # Default to the active bundle pointer, falling back to the known good one.
    $active = Join-Path $root 'build\toolchains\active.json'
    if (Test-Path $active) {
        $BundleRoot = (Get-Content $active -Raw | ConvertFrom-Json).root
    } else {
        $BundleRoot = 'D:\c28x-toolchain\b1-release\bundles\20261028-162823-7a7c48fc-ee53e7b7'
    }
}
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

# Feature + startup select the plain GPIO34 drive test or the exclusivity
# self-check (second take / second claim must be rejected).
$feature = if ($Exclusive) { 'bare-mmio-exclusive' } else { 'bare-mmio' }
$startupName = if ($Exclusive) { 'safe_gpio34_exclusive_start.asm' } else { 'safe_gpio34_ram_start.asm' }
$variant = if ($Exclusive) { 'safe-hal-gpio34-exclusive' } else { 'safe-hal-gpio34' }

$rustc = Join-Path $BundleRoot 'bin\rustc.exe'
$outDir = Join-Path $root ('build\' + $variant)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$src = Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs'
$obj = Join-Path $outDir 'hal.obj'
$startObj = Join-Path $outDir 'start.obj'
$supObj = Join-Path $outDir 'support.obj'
$firmware = Join-Path $outDir 'safe_hal_gpio34.out'
$map = Join-Path $outDir 'safe_hal_gpio34.map'
$argsFile = Join-Path $outDir 'args.rsp'

foreach ($p in @($rustc, $Compiler, $src,
                 (Join-Path $root ('platform\runtime\' + $startupName)),
                 (Join-Path $root 'platform\runtime\safe_gpio34_hal_support.asm'))) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing input: $p" }
}

function Fwd([string]$p) { return $p.Replace('\', '/') }

# 1. Compile the Safe HAL through the direct-object (LLVM) backend.
#    An @argfile avoids PowerShell's native-argument quote stripping for
#    `feature="..."`; paths use forward slashes so rustc does not treat the
#    backslashes as escapes.
$env:RUSTC_BOOTSTRAP = '1'
$argLines = @(
    '--edition=2021',
    '--target=c28x-none-elf',
    ('--sysroot=' + (Fwd $BundleRoot)),
    '--crate-type=lib',
    ('--emit=obj=' + (Fwd $obj)),
    '--cfg',
    ('feature="' + $feature + '"'),
    '--cfg',
    'feature="direct-obj-mmio"',
    '-Cpanic=abort',
    '-Copt-level=s',
    '-Zub-checks=no',
    '-Awarnings',
    (Fwd $src)
)
Set-Content -LiteralPath $argsFile -Value $argLines -Encoding ASCII
& $rustc "@$argsFile"
if ($LASTEXITCODE -ne 0) { throw 'safe-hal direct-object compile failed' }

# 2. Assemble the RAM startup shell and the leaf support routines.
foreach ($pair in @(@((Join-Path $root ('platform\runtime\' + $startupName)), $startObj),
                    @((Join-Path $root 'platform\runtime\safe_gpio34_hal_support.asm'), $supObj))) {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$($pair[1])" $pair[0]
    if ($LASTEXITCODE -ne 0) { throw "TI assembly failed: $($pair[0])" }
}

# 3. Link the RAM image.
& $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --entry_point=code_start --stack_size=0x100 --unused_section_elimination=on `
    "--map_file=$map" "--output_file=$firmware" `
    $startObj $supObj $obj `
    (Join-Path $root 'tools\F28035_ram.cmd') `
    (Join-Path $root 'tools\F28035_EABI_sections_ram.cmd')
if ($LASTEXITCODE -ne 0) { throw 'RAM link failed' }
if (-not (Test-Path -LiteralPath $firmware)) { throw 'Firmware output missing' }

Write-Host "SAFE_HAL_GPIO34_OBJ=$obj"
Write-Host "SAFE_HAL_GPIO34_FW=$firmware"
if ($BuildOnly) { return }

# 4. Hardware readback (GPIO34 only).
$dss = $Toolchain.Dss
$ccxml = Join-Path $root 'platform\vendor\ti\f2803x\common\targetConfigs\TMS320F28035.ccxml'
& $dss (Join-Path $PSScriptRoot 'verify-bare-gpio34-ram.js') $ccxml $firmware single
if ($LASTEXITCODE -ne 0) { throw 'DSS verify failed' }
Write-Host 'SAFE_HAL_GPIO34_VERIFY=PASS'
