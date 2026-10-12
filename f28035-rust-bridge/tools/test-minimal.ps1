# test-minimal.ps1 - Compile the no_std smoke program against the hand-built
# core + compiler_builtins rlibs. Codegen only (no link).
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
$std = Join-Path $root 'build\c28x-std'
$rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$env:RUSTC_BOOTSTRAP = '1'
$main = Join-Path $root 'test-minimal\src\main.rs'
$out  = Join-Path $std 'test-minimal.o'

$args = @('--edition=2021','--target=c28x-none-elf','--crate-type=lib',
  '-Cpanic=abort','-Crelocation-model=static','-Zforce-unstable-if-unmarked',
  '--crate-name=min_test',
  "--extern","core=$std\libcore.rlib",
  "--extern","compiler_builtins=$std\libcompiler_builtins.rlib",
  '--emit=obj','-o',$out,$main)
$r = Invoke-NativeCapture $rustc $args
Write-Host "exit=$($r.ExitCode), out exists=$(Test-Path $out)"
if ($r.ExitCode -ne 0) {
  $r.StdErr | Out-File (Join-Path $std 'test-minimal-err.txt') -Encoding utf8
  $r.StdErr | Select-String -Pattern 'error|LLVM|branch|Cannot|Assertion|missing' | Select-Object -Last 20
} else {
  Write-Host "test-minimal.o size: $((Get-Item $out).Length)"
}
