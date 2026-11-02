# verify-di3.ps1
# Regression gate for the 64-bit integer (di3) runtime.
#
# Compiles a tiny no_std crate that performs dynamic i64/u64 arithmetic:
#   x.wrapping_mul(y)            -> __muldi3
#   (x as u64).wrapping_div(..)  -> __udivdi3
#   (x as u64).wrapping_rem(..)  -> __umoddi3
# and links it against the ACTIVE B-1 bundle's ti-arithmetic.o + TI RTS. The
# C28x backend lowers these to GCC/compiler-rt libcalls. This gate fails (link
# error: undefined symbol) unless those routines are present in the bundle's
# ti-arithmetic.o. A second check confirms all eight di3 helpers
# (__muldi3/__divdi3/__moddi3/__udivdi3/__umoddi3/__ashldi3/__ashrdi3/__lshrdi3)
# are actually defined in the bundle's runtime object.
#
# The two core::panicking stubs referenced by wrapping div/rem are supplied as
# no-op loopers in the crate so the link test stays focused on the di3 gap.
#
# Usage:
#   . tools/llvm-c28x-env.ps1
#   . tools/verify-di3.ps1
# Optional: -TestBundle <path> links against a specific bundle root instead of
# the active one (used to demonstrate a negative control on a pre-fix bundle).

param(
    [string]$TestBundle = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
# toolchain-release.ps1 (Get-C28xBundle, $C28xToolchain helpers) lives in the
# b1 repo's tools dir, not the main repo.
. (Join-Path 'C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\tools' 'toolchain-release.ps1')

$bundle = if ($TestBundle) {
    [PSCustomObject]@{ Root = $TestBundle; Rustc = (Join-Path $TestBundle 'bin\rustc.exe') }
} else {
    Get-C28xBundle
}
$Rustc  = $bundle.Rustc
$libDir = Join-Path $bundle.Root 'lib\rustlib\c28x-none-elf\lib'
$arith  = Join-Path $libDir 'ti-arithmetic.o'
if (-not (Test-Path -LiteralPath $arith)) { throw "ti-arithmetic.o missing in bundle: $arith" }

$runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
$ramCmd  = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

# Minimal crate that forces the di3 libcalls. The two core panicking stubs are
# defined here (looping forever) so the link test resolves them without pulling
# all of libcore.
$testRs = @'
#![no_std]
#![no_main]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }

// Core panicking stubs referenced by wrapping div/rem (kept as no-op loopers).
#[no_mangle]
pub extern "C" fn _RNvNtNtCs1u5vVQ2WQ9_4core9panicking11panic_const23panic_const_div_by_zero() -> ! { loop {} }
#[no_mangle]
pub extern "C" fn _RNvNtNtCs1u5vVQ2WQ9_4core9panicking11panic_const23panic_const_rem_by_zero() -> ! { loop {} }

#[no_mangle]
pub extern "C" fn entry(x: i64, y: i64) -> i64 {
    let m = x.wrapping_mul(y);                  // __muldi3
    let u = (x as u64).wrapping_div(y as u64);  // __udivdi3
    let r = (x as u64).wrapping_rem(y as u64);  // __umoddi3
    m.wrapping_add(u as i64).wrapping_add(r as i64)
}
'@

$work    = Join-Path $env:TEMP 'c28x-di3'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$testRsPath = Join-Path $work 'di3.rs'
$testObjPath = Join-Path $work 'di3.obj'
$outPath = Join-Path $work 'di3.out'
$mapPath = Join-Path $work 'di3.map'
Set-Content -Path $testRsPath -Value $testRs -Encoding UTF8
Remove-Item $testObjPath, $outPath, $mapPath -ErrorAction SilentlyContinue

# Step 1: bundle rustc -> object (overflow checks off so only the di3 libcalls
# and the self-contained panicking loopers are referenced).
$compile = Invoke-NativeCapture $Rustc @('--target=c28x-none-elf', '-Cpanic=abort',
    '-Coverflow-checks=off', '--emit=obj', "-o", $testObjPath, $testRsPath)
if ($compile.ExitCode -ne 0) { throw "rustc failed: $($compile.StdErr)" }
if (-not (Test-Path $testObjPath)) { throw 'rustc did not produce object' }
Write-Host "OK: compiled di3 crate -> $testObjPath"

# Step 2: TI link against the bundle's ti-arithmetic.o + RTS.
$link = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--rom_model', '--stack_size=0x100', '--unused_section_elimination=off',
    '--entry_point=entry', "--map_file=$mapPath", "--output_file=$outPath",
    $testObjPath, $arith, $runtime, $ramCmd, $eabiCmd)
if ($link.StdOut) { Write-Host $link.StdOut }
if ($link.StdErr) { Write-Host $link.StdErr }
if ($link.ExitCode -ne 0) { throw "TI link failed (di3 runtime gap?): $($link.StdErr)" }
if (-not (Test-Path $outPath)) { throw 'TI link did not produce .out' }

# Step 3: confirm none of the di3 libcalls remain undefined.
$mapText = Get-Content -LiteralPath $mapPath -Raw
$undefTable = [regex]::Match($mapText, '(?s)undefined\s+first referenced.*?(?=\n\s*\n|\Z)')
$di3 = @('__muldi3','__divdi3','__moddi3','__udivdi3','__umoddi3','__ashldi3','__ashrdi3','__lshrdi3')
foreach ($sym in $di3) {
    if ($undefTable.Success -and $undefTable.Value -match [regex]::Escape($sym)) {
        throw "Unresolved di3 libcall: $sym"
    }
}
Write-Host "OK: TI linker produced $outPath; di3 libcalls resolved"

# Step 4: confirm all eight di3 helpers are defined in the bundle's runtime.
$bin = Split-Path -Parent $C28xToolchain.Cl2000
$nm = & "$bin\nm2000.exe" $arith | Out-String
foreach ($sym in $di3) {
    if ($nm -notmatch "\bT\b\s+$sym\b") {
        throw "Expected di3 symbol $sym not defined (T) in $arith"
    }
}
Write-Host "OK: all eight di3 helpers defined in $arith"
Write-Host '=== DI3 REGRESSION PASSED ===' -ForegroundColor Green
