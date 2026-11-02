# verify-f32-compare-convert.ps1
# Regression gate for the f32 compare / int<->float conversion runtime.
#
# Compiles a tiny no_std crate that performs dynamic f32 comparisons
# (a<b, a>b, a<=b, a>=b, a==b, a!=b) and i32<->f32 conversions
# (a as i32, a as u32, i as f32, u as f32) and links it against the
# ACTIVE B-1 bundle's ti-arithmetic.o + TI RTS. The C28x backend lowers
# these to GCC/compiler-rt libcalls (__lesf2/__gesf2/__gtsf2/__ltsf2/
# __eqsf2/__nesf2/__unordsf2/__fixsfsi/__fixunssfsi/__floatsisf/
# __floatunsisf). This gate fails (link error: undefined symbol) unless
# those routines are present in the bundle's ti-arithmetic.o.
#
# Usage:
#   . tools/llvm-c28x-env.ps1
#   . tools/verify-f32-compare-convert.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
# toolchain-release.ps1 (Get-C28xBundle, $C28xToolchain helpers) lives in the
# b1 repo's tools dir, not the main repo.
. (Join-Path 'C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\tools' 'toolchain-release.ps1')

# Resolve the active published B-1 bundle and its runtime inputs.
$bundle = Get-C28xBundle
$Rustc  = $bundle.Rustc
$libDir = Join-Path $bundle.Root 'lib\rustlib\c28x-none-elf\lib'
$arith  = Join-Path $libDir 'ti-arithmetic.o'
if (-not (Test-Path -LiteralPath $arith)) { throw "ti-arithmetic.o missing in active bundle: $arith" }

$runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
$ramCmd  = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

# Minimal crate that forces every f32 compare/convert libcall.
$testRs = @'
#![no_std]
#![no_main]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
#[no_mangle]
pub extern "C" fn entry(a: f32, b: f32) -> i32 {
    let mut s = 0i32;
    if a <  b { s += 1; }
    if a >  b { s += 1; }
    if a <= b { s += 1; }
    if a >= b { s += 1; }
    if a == b { s += 1; }
    if a != b { s += 1; }
    let i  = a as i32;
    let ui = a as u32;
    let f  = i as f32;
    let uf = ui as f32;
    let x  = a + b;
    s + i + (ui as i32) + (f as i32) + (uf as i32) + (x as i32)
}
'@

$work    = Join-Path $env:TEMP 'c28x-f32-compare-convert'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$testRsPath = Join-Path $work 'f32-compare-convert.rs'
$testObjPath = Join-Path $work 'f32-compare-convert.obj'
$outPath = Join-Path $work 'f32-compare-convert.out'
$mapPath = Join-Path $work 'f32-compare-convert.map'
Set-Content -Path $testRsPath -Value $testRs -Encoding UTF8
Remove-Item $testObjPath, $outPath, $mapPath -ErrorAction SilentlyContinue

# Step 1: bundle rustc -> object (overflow checks off so only the soft-float
# libcalls and the self-contained panic handler are referenced; this keeps
# the link inside the F28035 RAM map without pulling all of core).
$compile = Invoke-NativeCapture $Rustc @('--target=c28x-none-elf', '-Cpanic=abort',
    '-Coverflow-checks=off', '--emit=obj', "-o", $testObjPath, $testRsPath)
if ($compile.ExitCode -ne 0) { throw "rustc failed: $($compile.StdErr)" }
if (-not (Test-Path $testObjPath)) { throw 'rustc did not produce object' }
Write-Host "OK: compiled f32 compare/convert crate -> $testObjPath"

# Step 2: TI link against the active bundle's ti-arithmetic.o + RTS.
$link = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--rom_model', '--stack_size=0x100', '--unused_section_elimination=off',
    '--entry_point=entry', "--map_file=$mapPath", "--output_file=$outPath",
    $testObjPath, $arith, $runtime, $ramCmd, $eabiCmd)
if ($link.StdOut) { Write-Host $link.StdOut }
if ($link.StdErr) { Write-Host $link.StdErr }
if ($link.ExitCode -ne 0) { throw "TI link failed (f32 compare/convert runtime gap?): $($link.StdErr)" }
if (-not (Test-Path $outPath)) { throw 'TI link did not produce .out' }

# Step 3: confirm none of the soft-float libcalls remain undefined.
$mapText = Get-Content -LiteralPath $mapPath -Raw
$undefTable = [regex]::Match($mapText, '(?s)undefined\s+first referenced.*?(?=\n\s*\n|\Z)')
if ($undefTable.Success -and $undefTable.Value -match '\b__\w+sf\w*\b') {
    throw "Unresolved soft-float libcalls: $($undefTable.Value)"
}
# Explicitly require the compare/convert symbols to be defined in the bundle.
$required = @('__lesf2','__gesf2','__gtsf2','__ltsf2','__eqsf2','__nesf2','__unordsf2',
              '__fixsfsi','__fixunssfsi','__floatsisf','__floatunsisf')
foreach ($sym in $required) {
    if ($mapText -notmatch [regex]::Escape($sym)) {
        throw "Expected libcall $sym not present in linked image (runtime gap)"
    }
}
Write-Host "OK: TI linker produced $outPath; all f32 compare/convert libcalls resolved"
Write-Host '=== F32 COMPARE/CONVERT REGRESSION PASSED ===' -ForegroundColor Green
