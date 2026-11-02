# verify-mem-builtins.ps1
# Regression gate for the memory-routine pointer-convention fix.
#
# Before the fix the C28x backend, on a runtime-size copy, converted the Rust
# *logical byte* pointers to TI C WORD addresses (SRL 1) and emitted a plain
# `memcpy` libcall.  Rust's runtime memcpy is byte-address, so every runtime-size
# `copy_nonoverlapping`/`write_bytes` corrupted its destination (the isolated
# F28035 repro reached its end marker but copied nothing useful).
#
# After the fix the backend routes MEMCPY/MEMMOVE/MEMSET/MEMCMP/BCMP to the
# uniquely-named byte-address helpers c28x_memcpy / c28x_memmove / c28x_memset /
# c28x_memcmp / c28x_bcmp and performs NO byte->word conversion.  This gate fails
# unless:
#   1. the compiler emits c28x_memcpy / c28x_memset (NOT plain memcpy/memset),
#   2. the active B-1 bundle's builtins-dual.o (the compiled Rust
#      compiler_builtins object) DEFINES all five c28x_* helpers,
#   3. the TI link resolves them (no undefined c28x_* in the map).
#
# NOTE: the c28x_* helpers are Rust functions in crates/c28x-compiler-builtins,
# compiled into libcompiler_builtins.rlib, and ALSO published as the flat object
# builtins-dual.o by rebuild-core-sysroot.ps1.  They are NOT in ti-arithmetic.o
# (that object only carries the C arithmetic helpers such as __muldi3), so the
# gate inspects / links builtins-dual.o, not ti-arithmetic.o.
#
# Usage:
#   . tools/llvm-c28x-env.ps1
#   . tools/verify-mem-builtins.ps1
# Optional: -TestBundle <path> links against a specific bundle root instead of
# the active one (used to demonstrate a negative control on a pre-fix bundle,
# which emits plain `memcpy` and so fails the c28x_* assertions).

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
# The c28x_* helpers are Rust functions compiled into compiler_builtins and
# published as the flat object builtins-dual.o by rebuild-core-sysroot.ps1.
# This is what actually DEFINES c28x_memcpy/.. for the link (ti-arithmetic.o
# only carries the C arithmetic helpers).
$builtinsObj = Join-Path $libDir 'builtins-dual.o'
if (-not (Test-Path -LiteralPath $builtinsObj)) { throw "builtins-dual.o missing in bundle: $builtinsObj" }

$runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
$ramCmd  = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

# Minimal crate that forces runtime-size MEMCPY + MEMSET libcalls.  copy_/
# write_bytes with a runtime count cannot be expanded inline, so they lower to
# the c28x_memcpy / c28x_memset libcalls.
$testRs = @'
#![no_std]
#![no_main]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }

#[no_mangle]
pub extern "C" fn entry(dst: *mut u8, src: *const u8, n: usize) {
    unsafe {
        // runtime-size copy -> c28x_memcpy
        core::ptr::copy_nonoverlapping(src, dst, n);
        // runtime-size fill -> c28x_memset
        core::ptr::write_bytes(dst, 0xAAu8, n);
    }
}
'@

$work    = Join-Path $env:TEMP 'c28x-mem-builtins'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$testRsPath  = Join-Path $work 'mem.rs'
$testObjPath = Join-Path $work 'mem.obj'
$outPath = Join-Path $work 'mem.out'
$mapPath = Join-Path $work 'mem.map'
Set-Content -Path $testRsPath -Value $testRs -Encoding UTF8
Remove-Item $testObjPath, $outPath, $mapPath -ErrorAction SilentlyContinue

# Step 1: bundle rustc -> object.  The emitted libcall names prove the backend
# routing (c28x_* vs plain *).
$compile = Invoke-NativeCapture $Rustc @('--target=c28x-none-elf', '-Cpanic=abort',
    '-Zub-checks=no', '-Coverflow-checks=off',
    '--emit=obj', "-o", $testObjPath, $testRsPath)
if ($compile.ExitCode -ne 0) { throw "rustc failed: $($compile.StdErr)" }
if (-not (Test-Path $testObjPath)) { throw 'rustc did not produce object' }
Write-Host "OK: compiled mem-builtins crate -> $testObjPath"

# Step 2: the object must reference the byte-address c28x_* helpers and must NOT
# reference the plain memcpy/memset names (those belong to TI RTS, which uses
# word addresses and must never be pulled in for Rust-side copies).
$bin = Split-Path -Parent $C28xToolchain.Cl2000
$nmObj = & "$bin\nm2000.exe" $testObjPath | Out-String
foreach ($sym in @('c28x_memcpy','c28x_memset')) {
    if ($nmObj -notmatch "\bU\b\s+$sym\b") {
        throw "Expected runtime-size libcall $sym to be referenced (U) by the object; backend routing may be missing."
    }
}
foreach ($sym in @('memcpy','memmove','memset','memcmp')) {
    if ($nmObj -match "\bU\b\s+$sym\b") {
        throw "Object references plain '$sym' — backend must route to c28x_* (byte-address) helpers, not TI RTS names."
    }
}
Write-Host 'OK: object references c28x_memcpy/c28x_memset, no plain memcpy/memset'

# Step 3: TI link against the bundle's ti-arithmetic.o + RTS.
$link = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--rom_model', '--stack_size=0x100', '--unused_section_elimination=on',
    '--entry_point=entry', "--map_file=$mapPath", "--output_file=$outPath",
    $testObjPath, $builtinsObj, (Join-Path $libDir 'core-dual.o'), $arith, $runtime, $ramCmd, $eabiCmd)
if ($link.StdOut) { Write-Host $link.StdOut }
if ($link.StdErr) { Write-Host $link.StdErr }
if ($link.ExitCode -ne 0) { throw "TI link failed (c28x_* runtime gap?): $($link.StdErr)" }
if (-not (Test-Path $outPath)) { throw 'TI link did not produce .out' }

# Step 4: confirm none of the c28x_* helpers remain undefined in the link.
$mapText = Get-Content -LiteralPath $mapPath -Raw
$undefTable = [regex]::Match($mapText, '(?s)undefined\s+first referenced.*?(?=\n\s*\n|\Z)')
foreach ($sym in @('c28x_memcpy','c28x_memmove','c28x_memset','c28x_memcmp','c28x_bcmp')) {
    if ($undefTable.Success -and $undefTable.Value -match [regex]::Escape($sym)) {
        throw "Unresolved c28x_* libcall: $sym"
    }
}
Write-Host "OK: TI linker produced $outPath; c28x_* libcalls resolved"

# Step 5: confirm all five byte-address helpers are defined (T) in the bundle's
# builtins-dual.o (the compiled Rust compiler_builtins object).
$nmBuiltins = & "$bin\nm2000.exe" $builtinsObj | Out-String
foreach ($sym in @('c28x_memcpy','c28x_memmove','c28x_memset','c28x_memcmp','c28x_bcmp')) {
    if ($nmBuiltins -notmatch "\bT\b\s+$sym\b") {
        throw "Expected $sym not defined (T) in $builtinsObj"
    }
}
# And the plain TI-RTS names must NOT be defined by our runtime (otherwise they
# could shadow TI's word-address memcpy at link time and corrupt interop).
foreach ($sym in @('memcpy','memmove','memset','memcmp')) {
    if ($nmBuiltins -match "\bT\b\s+$sym\b") {
        throw "Our runtime must NOT define plain '$sym' (collides with TI RTS word-address $sym): $builtinsObj"
    }
}
Write-Host "OK: all five c28x_* helpers defined in $builtinsObj; plain names absent"

Write-Host '=== MEMORY BUILTINS REGRESSION PASSED ===' -ForegroundColor Green
