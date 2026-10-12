# rust-to-c28x-obj.ps1
# Rust source -> LLVM IR -> C28x .obj -> TI link -> .out
#
# Pipeline:
#   rustc --emit=llvm-ir (existing nightly)  -> .ll
#   patch triple/datalayout for C28x
#   llc -mtriple=c28x-ti-none -filetype=obj -> .obj
#   cl2000 --run_linker (with RTS + TI stubs) -> .out
#
# Usage:
#   . tools/llvm-c28x-env.ps1
#   . tools/rust-to-c28x-obj.ps1 -RustFile path\to\main.rs
#
# Currently supports: no_std functions that only make external calls
# (LCR) and return. Arithmetic like add/sub needs ADD32rr encoding
# (TODO in the LLVM backend).

param(
    [Parameter(Mandatory=$true)]
    [string]$RustFile,
    [string]$OutName = 'rust_app'
)

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$rustc = "C:\Users\61987\.rustup\toolchains\nightly-2026-09-14-x86_64-pc-windows-msvc\bin\rustc.exe"
if (-not (Test-Path $rustc)) { throw "rustc not found: $rustc" }

$work = Join-Path $env:TEMP "rust-c28x-build"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$base = [IO.Path]::GetFileNameWithoutExtension($RustFile)
$llPath = Join-Path $work "$base.ll"
$c28xLlPath = Join-Path $work "$base.c28x.ll"
$rustObjPath = Join-Path $work "$base.obj"

# --- Step 1: rustc -> LLVM IR ---------------------------------------------
Write-Host "==> [1/5] rustc --emit=llvm-ir"
& $rustc --emit=llvm-ir --crate-type=rlib -C panic=abort -C overflow-checks=off $RustFile -o $llPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "rustc failed" }
Write-Host "    $llPath ($((Get-Item $llPath).Length) bytes)"

# --- Step 2: patch triple/datalayout --------------------------------------
Write-Host "==> [2/5] patch triple/datalayout for C28x"
$content = Get-Content $llPath -Raw
$content = $content -replace 'target datalayout = ".*"', 'target datalayout = "e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16"'
$content = $content -replace 'target triple = ".*"', 'target triple = "c28x-ti-none"'
[IO.File]::WriteAllText($c28xLlPath, $content, [Text.UTF8Encoding]::new($false))

# --- Step 3: llc -> .obj ---------------------------------------------------
Write-Host "==> [3/5] C28x llc -filetype=obj"
& $C28xToolchain.Llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj $c28xLlPath -o $rustObjPath 2>&1
if ($LASTEXITCODE -ne 0) { throw "llc failed" }
if (-not (Test-Path $rustObjPath)) { throw "llc did not produce .obj" }
Write-Host "    $rustObjPath ($((Get-Item $rustObjPath).Length) bytes)"

# --- Step 4: TI stubs (callee + main) -------------------------------------
Write-Host "==> [4/5] assemble TI stubs"
# Discover external symbols the Rust code calls, so we can stub them.
$extSymbols = Select-String -Path $llPath -Pattern '^declare .*@(\w+)\(' | ForEach-Object {
    $_.Matches[0].Groups[1].Value
} | Where-Object { $_ -notmatch '^(llvm\.|__CxxFrame|_RNv)' }

$NL = "`r`n"
$calleeAsm = "        .sect `".text`"$NL"
foreach ($sym in $extSymbols) {
    $calleeAsm += "        .def $sym; .globalsym; .endef${NL}${sym}:${NL}        lretr$NL"
}
$calleePath = Join-Path $work "stub_callee.asm"
[IO.File]::WriteAllText($calleePath, $calleeAsm, [Text.ASCIIEncoding]::new())

# main calls the first non-stub Rust function (rust_caller or user_main).
$entrySym = Select-String -Path $llPath -Pattern '^define .*@(\w+)\(' | ForEach-Object {
    $_.Matches[0].Groups[1].Value
} | Select-Object -First 1
if (-not $entrySym) { throw "No define function found in IR" }
Write-Host "    entry: $entrySym"

$mainAsm = "        .sect `".text`"$NL" +
           "        .def main; .globalsym; .endef$NL" +
           "        .ref $entrySym$NL" +
           "main:$NL" +
           "        lcr $entrySym$NL" +
           "        lretr$NL"
$mainPath = Join-Path $work "stub_main.asm"
[IO.File]::WriteAllText($mainPath, $mainAsm, [Text.ASCIIEncoding]::new())

$compileFlags = @('--silicon_version=28','--abi=eabi','--compile_only','-v28')
$calleeObjPath = Join-Path $work "stub_callee.obj"
$mainObjPath   = Join-Path $work "stub_main.obj"
& $C28xToolchain.Cl2000 @compileFlags --output_file=$calleeObjPath $calleePath 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "assemble callee stub failed" }
& $C28xToolchain.Cl2000 @compileFlags --output_file=$mainObjPath $mainPath 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "assemble main stub failed" }

# --- Step 5: TI link -------------------------------------------------------
Write-Host "==> [5/5] TI linker"
$runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
$ramCmd  = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

$outPath = Join-Path $work "$OutName.out"
$mapPath = Join-Path $work "$OutName.map"
Remove-Item $outPath,$mapPath -ErrorAction SilentlyContinue

& $C28xToolchain.Cl2000 `
    --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --rom_model --stack_size=0x100 --unused_section_elimination=off `
    --map_file=$mapPath --output_file=$outPath `
    $rustObjPath $calleeObjPath $mainObjPath $runtime $ramCmd $eabiCmd
if ($LASTEXITCODE -ne 0) { throw "TI link failed" }
if (-not (Test-Path $outPath)) { throw "TI link did not produce .out" }

Write-Host ""
Write-Host "=== SUCCESS ===" -ForegroundColor Green
Write-Host "Rust source: $RustFile"
Write-Host "Rust .obj:   $rustObjPath"
Write-Host "Linked .out:  $outPath ($((Get-Item $outPath).Length) bytes)"
Write-Host ""
Write-Host "Disassembly of entry:"
& $C28xToolchain.Dis2000 $outPath 2>&1 | Select-String -Pattern "$entrySym|main:" -Context 0,4 | Select-Object -First 10
