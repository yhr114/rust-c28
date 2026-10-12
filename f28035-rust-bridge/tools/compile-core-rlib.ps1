# compile-core-rlib.ps1 — Compile core (and compiler_builtins) to .rlib for c28x-none-elf.
# Reproduces the prior metadata approach but escalates to --emit=link so a real
# .rlib (metadata + machine code objects) is produced, surfacing the LLVM codegen
# errors ("unsupported library call operation") that block gap 4.
param(
  [string]$Rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe',
  [string]$Emit = 'link'   # 'link' -> .rlib with objects ; 'metadata' -> .rmeta
)

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'build\c28x-std'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$sysroot = (& $Rustc --print sysroot).Trim()
$library = Join-Path $sysroot 'lib\rustlib\src\rust\library'
$coreSource = Join-Path $library 'core\src\lib.rs'
$builtinsSource = Join-Path $library 'compiler-builtins\compiler-builtins\src\lib.rs'

$env:RUSTC_BOOTSTRAP = '1'

$coreOut = Join-Path $outDir 'libcore.rlib'
$builtinsOut = Join-Path $outDir 'libcompiler_builtins.rlib'

$common = @('--edition=2024', '--target=c28x-none-elf', '--crate-type=lib',
    "--emit=$Emit", '-Cpanic=abort', '-Crelocation-model=static',
    '-Zforce-unstable-if-unmarked', '-Awarnings')

Write-Host "sysroot=$sysroot"
Write-Host "emit=$Emit"
Write-Host "==> Compiling core"
$r = Invoke-NativeCapture $Rustc (@($common) + @('--crate-name=core', '-o', $coreOut, $coreSource))
Write-Host "core exit=$($r.ExitCode)"
if ($r.ExitCode -ne 0) {
    Write-Host "---- core STDERR ----"
    $r.StdErr
    $log = Join-Path $root 'build-logs\core-rlib-err.log'
    New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
    ($r.StdErr) | Out-File $log -Encoding utf8
    Write-Host "stderr saved to $log"
    exit 1
}
Write-Host "core rlib size: $((Get-Item $coreOut).Length)"

Write-Host "==> Compiling compiler_builtins"
$r2 = Invoke-NativeCapture $Rustc (@($common) + @('--crate-name=compiler_builtins',
    '--cfg', 'feature="compiler-builtins"',
    '--extern', "core=$coreOut",
    '-o', $builtinsOut, $builtinsSource))
Write-Host "builtins exit=$($r2.ExitCode)"
if ($r2.ExitCode -ne 0) {
    Write-Host "---- builtins STDERR ----"
    $r2.StdErr
    $log = Join-Path $root 'build-logs\builtins-rlib-err.log'
    ($r2.StdErr) | Out-File $log -Encoding utf8
    Write-Host "stderr saved to $log"
    exit 1
}
Write-Host "builtins rlib size: $((Get-Item $builtinsOut).Length)"
Write-Host "OK"
