# build-core-rlib.ps1 - Build core rlib: dual emit metadata+obj in one run (so the
# metadata carries optimized MIR for downstream monomorphization), then package by
# hand (the direct --emit=link path hits "inline asm not supported" because C28x
# has no asm parser and rustc's rlib metadata-section emission uses inline asm).
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
$std = Join-Path $root 'build\c28x-std'
New-Item -ItemType Directory -Path $std -Force | Out-Null
$rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$env:RUSTC_BOOTSTRAP = '1'
$sysroot = (& $rustc --print sysroot).Trim()
$coreSrc = Join-Path $sysroot 'lib\rustlib\src\rust\library\core\src\lib.rs'

$common = @('--edition=2024','--target=c28x-none-elf','--crate-type=lib',
  '-Cpanic=abort','-Crelocation-model=static','-Zforce-unstable-if-unmarked','-Awarnings',
  '--crate-name=core','--crate-type=rlib')

Write-Host "==> core dual emit (metadata+obj)"
$r = Invoke-NativeCapture $rustc (@($common) + @(
  '--emit=metadata,obj',
  '-o',(Join-Path $std 'core-dual'),
  $coreSrc))
Write-Host "exit=$($r.ExitCode)"
# dual emit writes core-dual.rmeta and core-dual.cgu.0.rcgu.o? inspect
Get-ChildItem $std -Filter 'core-dual*' | Select-Object Name,Length
if ($r.ExitCode -ne 0) { $r.StdErr | Select-Object -First 15; throw "core dual emit failed" }
