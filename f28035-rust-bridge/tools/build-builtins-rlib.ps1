# build-builtins-rlib.ps1 - Build a MINIMAL compiler_builtins rlib from the
# project's crates/c28x-compiler-builtins (mem{cpy,set,move,cmp} Rust impls +
# extern decls for __divsi3 etc.). The upstream compiler-builtins crate pulls in
# the whole float/libm stack which generates functions larger than C28x's
# +/-32767-word conditional-branch range. Minimal = small functions, compiles.
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
$std = Join-Path $root 'build\c28x-std'
$rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$env:RUSTC_BOOTSTRAP = '1'
$builtinsSrc = Join-Path $root 'crates\c28x-compiler-builtins\src\lib.rs'
$coreRlib = Join-Path $std 'libcore.rlib'
if (-not (Test-Path $builtinsSrc)) { throw "missing $builtinsSrc" }

$common = @('--edition=2021','--target=c28x-none-elf','--crate-type=lib',
  '-Cpanic=abort','-Crelocation-model=static','-Zforce-unstable-if-unmarked','-Awarnings',
  '--crate-name=compiler_builtins','--crate-type=rlib',
  "--extern","core=$coreRlib")

Write-Host "==> minimal builtins dual emit (metadata+obj)"
$r = Invoke-NativeCapture $rustc (@($common) + @(
  '--emit=metadata,obj',
  '-o',(Join-Path $std 'builtins-dual'),
  $builtinsSrc))
Write-Host "exit=$($r.ExitCode)"
if ($r.ExitCode -ne 0) {
  $r.StdErr | Out-File (Join-Path $std 'builtins-err.txt') -Encoding utf8
  $r.StdErr | Select-String -Pattern 'error|LLVM|branch|Cannot|Assertion' | Select-Object -Last 15
  throw "builtins dual emit failed"
}
Get-ChildItem $std -Filter 'libcompiler_builtins*' | Select-Object Name,Length
Get-ChildItem $std -Filter 'builtins-dual*' | Select-Object Name,Length

# package
$stage = Join-Path $std 'rlib-stage-builtins'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item (Join-Path $std 'libcompiler_builtins.rmeta') (Join-Path $stage 'lib.rmeta') -Force
Copy-Item (Join-Path $std 'builtins-dual.o') (Join-Path $stage 'builtins-cgu.0.rcgu.o') -Force
$ar = 'D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin\llvm-ar.exe'
$rlib = Join-Path $std 'libcompiler_builtins.rlib'
if (Test-Path $rlib) { Remove-Item $rlib -Force }
Push-Location $stage
& $ar rcs $rlib 'lib.rmeta' 'builtins-cgu.0.rcgu.o'
Pop-Location
Write-Host "builtins rlib size: $((Get-Item $rlib).Length)"
Write-Host "OK"
