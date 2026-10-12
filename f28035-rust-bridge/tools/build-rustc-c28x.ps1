# Rebuild the patched GNU-host stage1 rustc against the existing C28x LLVM build.
param(
    [string]$RustSource = 'D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad',
    [string]$Python = 'C:\Users\61987\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [int]$Jobs = 2,
    [switch]$BuildHostStd
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
if ($Jobs -lt 1) { throw 'Jobs must be at least 1' }
if (-not (Test-Path -LiteralPath (Join-Path $RustSource 'x.py'))) { throw "Rust source missing: $RustSource" }
$bootstrap = Join-Path $RustSource 'bootstrap.toml'
if (-not (Test-Path -LiteralPath $bootstrap)) {
    $template = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\llvm-c28x\rustc-patches\bootstrap-windows-gnu.toml'
    Copy-Item -LiteralPath $template -Destination $bootstrap
}
if (-not (Test-Path -LiteralPath $Python)) { throw "Python not found: $Python" }

$gnu = 'D:\c28x-toolchain\rustup-gnu\toolchains\nightly-2026-09-14-x86_64-pc-windows-gnu'
$selfBin = Join-Path $gnu 'lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained'
$selfLib = Join-Path $gnu 'lib\rustlib\x86_64-pc-windows-gnu\lib\self-contained'
$linker = Join-Path $selfBin 'x86_64-w64-mingw32-gcc.exe'
if (-not (Test-Path -LiteralPath $linker)) { throw "GNU linker missing: $linker" }
if (-not (Test-Path -LiteralPath (Join-Path $C28xToolchain.Build 'bin\llvm-config.exe'))) {
    throw 'Patched LLVM build missing'
}
$env:RUSTUP_HOME = 'D:\c28x-toolchain\rustup-gnu'
$env:PATH = "D:\mingw64\bin;$selfBin;$gnu\bin;$env:PATH"
$env:LIBRARY_PATH = "D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\x86_64-w64-mingw32\lib;$selfLib;D:\mingw64\x86_64-w64-mingw32\lib"
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = $linker
$temp = 'E:\c28x-rust-temp'
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$env:TEMP = $temp
$env:TMP = $temp

. (Join-Path $PSScriptRoot 'llvm-build-fingerprint.ps1')
$fingerprint = Get-C28xLlvmFingerprint $C28xToolchain.Build
$statePath = Join-Path $RustSource '.c28x-rustc-llvm-fingerprint'
$previousFingerprint = if (Test-Path -LiteralPath $statePath) { (Get-Content -LiteralPath $statePath -Raw).Trim() } else { '' }
if ($previousFingerprint -ne $fingerprint) {
    # rustc_llvm/build.rs watches llvm-config but not each external archive.
    # Invalidate that dependency only when LLVM content changed (or on first use).
    (Get-Item -LiteralPath (Join-Path $C28xToolchain.Build 'bin\llvm-config.exe')).LastWriteTime = Get-Date
    Write-Host 'LLVM content changed or has no recorded successful build; refresh rustc LLVM dependency.'
} else {
    Write-Host 'LLVM content unchanged; reuse existing rustc LLVM dependency.'
}

Push-Location $RustSource
try {
    & $Python x.py build --stage 1 --jobs $Jobs compiler/rustc
    if ($LASTEXITCODE -ne 0) { throw "stage1 rustc build failed: exit $LASTEXITCODE" }
    # Never record a failed build as reusable. x.py/Cargo still checks all Rust
    # sources, dependencies, flags and missing artifacts on every invocation.
    [IO.File]::WriteAllText($statePath, $fingerprint)
    if ($BuildHostStd) {
        & $Python x.py build --stage 1 --jobs $Jobs library/std
        if ($LASTEXITCODE -ne 0) { throw "stage1 host std build failed: exit $LASTEXITCODE" }
    }
} finally {
    Pop-Location
}
Write-Output "C28x rustc: D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe"
