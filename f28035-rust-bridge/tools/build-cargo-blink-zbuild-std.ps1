# build-cargo-blink-zbuild-std.ps1 - Native -Zbuild-std build of c28x-gpio-blink.
#
# Replaces the old --sysroot flow (config.toml.bak-sysroot). Core and
# compiler_builtins are compiled on the fly from the patched rustc's rust-src.
#
# Output: crates/c28x-gpio-blink/gpio-blink.o (TI cl2000 links it later).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$crate = Join-Path $root 'crates\c28x-gpio-blink'
$cargo = 'C:\Users\61987\.cargo\bin\cargo.exe'

$env:RUSTC_BOOTSTRAP = '1'
$env:CARGO_TERM_COLOR = 'never'

Set-Location $crate
$obj = Join-Path $crate 'gpio-blink.o'
Remove-Item $obj -ErrorAction SilentlyContinue

& $cargo rustc '-Zbuild-std=core,compiler_builtins' --release --target c28x-none-elf -- --emit=obj -o $obj
if ($LASTEXITCODE -ne 0) { throw "cargo rustc failed (rc=$LASTEXITCODE)" }
if (-not (Test-Path $obj)) { throw "missing $obj" }

Write-Host "OK: $obj ($((Get-Item $obj).Length) bytes)"
