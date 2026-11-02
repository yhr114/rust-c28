#Requires -Version 5.1
# Build + verify the integrated business loop on real hardware.
#
# This is the joint validation the single-purpose cases cannot give: one image
# runs the closed chain an application actually uses.
#   - main (Safe HAL `bare-mmio-business`): system_init, ADC SOC0 on channel 0,
#     ePWM1 at 1000 ticks with GPIO0/EPWM1A muxed, SCI-A internal loopback,
#     then Timer0 periodic 1 ms with the CPU interrupt enabled;
#   - TINT0 ISR: sample ADC (bounded EOC wait) -> duty = raw*period/4095 ->
#     write PWM compare -> every 4th tick exchange a status byte on SCI-A;
#   - main loop keeps running in parallel and increments a liveness counter.
# The DSS readback cross-checks the ADC result register against the CMPA the
# firmware wrote, proves TBCTR is advancing, and requires zero SCI/ADC errors.
param(
    [string]$BundleRoot = '',
    [string]$Compiler = '',
    [switch]$BuildOnly,
    [switch]$LongRun,
    [switch]$DirectCalls,
    [switch]$Checked,
    [int]$Duration = 30
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $BundleRoot) {
    # Prefer the local pointer; otherwise follow the canonical B-1 release
    # pointer so the default build always tracks the accepted active bundle
    # (20261102-122629 carries the byte-RMW fix that makes the method-call
    # path work, so a stale fallback would silently reintroduce the bug).
    $active = Join-Path $root 'build\toolchains\active.json'
    if (-not (Test-Path $active)) {
        $active = Join-Path (Split-Path -Parent $root) 'f28035-rust-bridge-b1\build\toolchains\active.json'
    }
    if (Test-Path $active) {
        $BundleRoot = (Get-Content $active -Raw | ConvertFrom-Json).root
    } else {
        $BundleRoot = 'D:\c28x-toolchain\b1-release\bundles\20261102-122629-cf4b3949-7bc20a44'
    }
}
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

# The business loop has two code paths gated by `feature="business-direct-ffi"`:
#   * method-call (default)     -> the NORMAL path.  Since the 2026-11-02
#     byte-RMW backend fix (active bundle 20261102-122629) it passes the full
#     short/long regression, so no workaround is needed.
#   * direct-ffi (-DirectCalls) -> legacy free-function comparison path.
# The switch is kept only to reproduce/compare the historical workaround.

$rustc = Join-Path $BundleRoot 'bin\rustc.exe'
$variant = if ($DirectCalls) { 'safe-hal-business-direct' } else { 'safe-hal-business' }
if ($Checked) { $variant += '-checked' }
$outDir = Join-Path $root ('build\' + $variant)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$src = Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs'
$obj = Join-Path $outDir 'hal.obj'
$asmObj = Join-Path $outDir 'rt-asm.obj'
$intObj = Join-Path $outDir 'rt-int.obj'
$deviceCalObj = Join-Path $outDir 'device-cal.obj'
$firmware = Join-Path $outDir 'business.out'
$map = Join-Path $outDir 'business.map'
$argsFile = Join-Path $outDir 'args.rsp'
$lib = Join-Path (Split-Path -Parent (Split-Path -Parent $Compiler)) 'lib\rts2800_ml_eabi.lib'
# Runtime closure: the duty computation is a real u32 divide, so the link needs
# the published builtins (__udivsi3/__udivmodsi4) and ti-arithmetic adapters,
# exactly like the Cargo path.
$rtLib = Join-Path $BundleRoot 'lib\rustlib\c28x-none-elf\lib'
$builtinsObj = Join-Path $rtLib 'builtins-dual.o'
$coreObj = Join-Path $rtLib 'core-dual.o'
$arithmeticObj = Join-Path $rtLib 'ti-arithmetic.o'
foreach ($p in @($builtinsObj, $coreObj, $arithmeticObj, $lib)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing runtime input: $p" }
}

function Fwd([string]$p) { return $p.Replace('\', '/') }

# 1. Compile the Safe HAL (direct-object) with the business feature.
$env:RUSTC_BOOTSTRAP = '1'
$rustArgs = @(
    '--edition=2021',
    '--target=c28x-none-elf',
    ('--sysroot=' + (Fwd $BundleRoot)),
    '--crate-type=lib',
    ('--emit=obj=' + (Fwd $obj)),
    '--cfg', 'feature="bare-mmio-business"',
    '--cfg', 'feature="direct-obj-mmio"',
    '-Cpanic=abort', '-Copt-level=s', '-Zub-checks=no', '-Awarnings'
)
# -Checked turns on the debug/checked path (overflow + debug assertions) so the
# code that previously "entered an exception" with checks on is exercised.
if ($Checked) { $rustArgs += @('-Coverflow-checks=yes', '-Cdebug-assertions=yes') }
$rustArgs += (Fwd $src)
if ($DirectCalls) { $rustArgs += @('--cfg', 'feature="business-direct-ffi"') }
Set-Content -LiteralPath $argsFile -Encoding ASCII -Value $rustArgs
& $rustc "@$argsFile"
if ($LASTEXITCODE -ne 0) { throw 'safe-hal business compile failed' }

# 2. Assemble the full c28x-rt startup and the TINT0_ISR trampoline, and
#    compile the Device_cal shim (calls the boot-ROM ADC calibration).
foreach ($pair in @(@((Join-Path $root 'crates\c28x-rt\asm.s'), $asmObj),
                    @((Join-Path $root 'crates\c28x-rt\interrupts.s'), $intObj),
                    @((Join-Path $root 'platform\runtime\device_cal.c'), $deviceCalObj))) {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$($pair[1])" $pair[0]
    if ($LASTEXITCODE -ne 0) { throw "TI assembly failed: $($pair[0])" }
}

# 3. Link the full RAM image.
& $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --entry_point=code_start --stack_size=0x200 --unused_section_elimination=on `
    "--map_file=$map" "--output_file=$firmware" `
    $asmObj $intObj $deviceCalObj $obj $coreObj $builtinsObj $arithmeticObj $lib `
    (Join-Path $root 'crates\c28x-rt\ram.cmd')
if ($LASTEXITCODE -ne 0) { throw 'RAM link failed' }
if (-not (Test-Path -LiteralPath $firmware)) { throw 'Firmware output missing' }

Write-Host "SAFE_HAL_BUSINESS_FW=$firmware"
if ($BuildOnly) { return }

# 4. Hardware readback: ADC -> duty -> CMPA, SCI frames, time base advancing.
$dss = $Toolchain.Dss
$ccxml = Join-Path $root 'platform\vendor\ti\f2803x\common\targetConfigs\TMS320F28035.ccxml'
if ($LongRun) {
    $reader = Join-Path $PSScriptRoot 'verify-safe-hal-business-long.js'
    $readArgs = @($reader, $ccxml, $firmware, [string]$Duration)
    $marker = '(?m)^SAFE_HAL_LONG_RUN=PASS\r?$'
} else {
    $reader = Join-Path $PSScriptRoot 'verify-safe-hal-business.js'
    $readArgs = @($reader, $ccxml, $firmware)
    $marker = '(?m)^SAFE_HAL_BUSINESS_LOOP=PASS\r?$'
}
$result = Invoke-NativeCapture $dss $readArgs
$logPath = Join-Path $outDir $(if($LongRun){'hardware-long.log'}else{'hardware.log'})
[IO.File]::WriteAllText($logPath, $result.StdOut + $result.StdErr)
Write-Host ($result.StdOut + $result.StdErr)
if ($result.ExitCode -or $result.StdOut -notmatch $marker) {
    throw "Business hardware verification failed; inspect $logPath"
}
if ($LongRun) { Write-Host 'SAFE_HAL_BUSINESS_LONG_VERIFY=PASS' }
else { Write-Host 'SAFE_HAL_BUSINESS_VERIFY=PASS' }
