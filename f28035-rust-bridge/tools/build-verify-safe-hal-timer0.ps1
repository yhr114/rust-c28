#Requires -Version 5.1
# Build + verify the Safe HAL Timer0 interrupt self-check on real hardware.
#
# This exercises the FULL application flow (not a single bare entry):
#   - the Safe HAL compiles with `bare-mmio-timer` + `direct-obj-mmio` and its
#     `main` starts Timer0, enables the interrupt via PeriodicTimer0::enable_interrupt
#     (IER group 1 + EINT), and drives GPIO34 low once the TINT0 ISR has fired;
#   - the c28x-rt full startup (crates/c28x-rt/asm.s: code_start + _pie_table)
#     installs TINT0_ISR from interrupts.s as the PIE vector and calls main;
#   - TINT0_ISR trampoline calls rust_timer0_isr, clears TCR.TIF, acks PIE group 1.
# The DSS readback (GPIO34 low) proves the automatic IER/EINT/PIE-ack path.
param(
    [string]$BundleRoot = '',
    [string]$Compiler = '',
    [switch]$BuildOnly
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $BundleRoot) {
    $active = Join-Path $root 'build\toolchains\active.json'
    if (Test-Path $active) {
        $BundleRoot = (Get-Content $active -Raw | ConvertFrom-Json).root
    } else {
        $BundleRoot = 'D:\c28x-toolchain\b1-release\bundles\20261028-162823-7a7c48fc-ee53e7b7'
    }
}
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

$rustc = Join-Path $BundleRoot 'bin\rustc.exe'
$outDir = Join-Path $root 'build\safe-hal-timer0'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$src = Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs'
$obj = Join-Path $outDir 'hal.obj'
$asmObj = Join-Path $outDir 'rt-asm.obj'
$intObj = Join-Path $outDir 'rt-int.obj'
$firmware = Join-Path $outDir 'timer0.out'
$map = Join-Path $outDir 'timer0.map'
$argsFile = Join-Path $outDir 'args.rsp'
$lib = Join-Path (Split-Path -Parent (Split-Path -Parent $Compiler)) 'lib\rts2800_ml_eabi.lib'

function Fwd([string]$p) { return $p.Replace('\', '/') }

# 1. Compile the Safe HAL (direct-object) with the timer feature.
$env:RUSTC_BOOTSTRAP = '1'
Set-Content -LiteralPath $argsFile -Encoding ASCII -Value @(
    '--edition=2021',
    '--target=c28x-none-elf',
    ('--sysroot=' + (Fwd $BundleRoot)),
    '--crate-type=lib',
    ('--emit=obj=' + (Fwd $obj)),
    '--cfg', 'feature="bare-mmio-timer"',
    '--cfg', 'feature="direct-obj-mmio"',
    '-Cpanic=abort', '-Copt-level=s', '-Zub-checks=no', '-Awarnings',
    (Fwd $src)
)
& $rustc "@$argsFile"
if ($LASTEXITCODE -ne 0) { throw 'safe-hal timer compile failed' }

# 2. Assemble the full c28x-rt startup and the TINT0_ISR trampoline.
foreach ($pair in @(@((Join-Path $root 'crates\c28x-rt\asm.s'), $asmObj),
                    @((Join-Path $root 'crates\c28x-rt\interrupts.s'), $intObj))) {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$($pair[1])" $pair[0]
    if ($LASTEXITCODE -ne 0) { throw "TI assembly failed: $($pair[0])" }
}

# 3. Link the full RAM image (TI runtime + c28x-rt ram.cmd provide the bss/data
#    / stack symbols that asm.s references).
& $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --entry_point=code_start --stack_size=0x200 --unused_section_elimination=on `
    "--map_file=$map" "--output_file=$firmware" `
    $asmObj $intObj $obj $lib (Join-Path $root 'crates\c28x-rt\ram.cmd')
if ($LASTEXITCODE -ne 0) { throw 'RAM link failed' }
if (-not (Test-Path -LiteralPath $firmware)) { throw 'Firmware output missing' }

Write-Host "SAFE_HAL_TIMER0_FW=$firmware"
if ($BuildOnly) { return }

# 4. Hardware readback (GPIO34 low after the ISR fires).
$dss = $Toolchain.Dss
$ccxml = Join-Path $root 'platform\vendor\ti\f2803x\common\targetConfigs\TMS320F28035.ccxml'
& $dss (Join-Path $PSScriptRoot 'verify-safe-hal-timer0.js') $ccxml $firmware
if ($LASTEXITCODE -ne 0) { throw 'DSS verify failed' }
Write-Host 'SAFE_HAL_TIMER0_VERIFY=PASS'
