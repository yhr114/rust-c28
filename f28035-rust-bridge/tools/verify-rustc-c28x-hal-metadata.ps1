# Target-specific type checking without invoking incomplete C28x machine code generation.
param(
    [string]$Rustc = '',
    [string]$Case1Source = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $Rustc) { $Rustc = $env:C28X_RUSTC }
if (-not $Rustc) { $Rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe' }
if (-not (Test-Path -LiteralPath $Rustc)) { throw "C28x rustc not found: $Rustc" }
if (-not $Case1Source) {
    $Case1Source = Join-Path (Split-Path -Parent $root) 'example\case1\src\main.rs'
}
if (-not (Test-Path -LiteralPath $Case1Source)) { throw "case1 source not found: $Case1Source" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'build\rustc-c28x-metadata' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$sysrootResult = Invoke-NativeCapture $Rustc @('--print', 'sysroot')
if ($sysrootResult.ExitCode -ne 0) { throw "Cannot query rustc sysroot: $($sysrootResult.StdErr)" }
$library = Join-Path $sysrootResult.StdOut.Trim() 'lib\rustlib\src\rust\library'
$coreSource = Join-Path $library 'core\src\lib.rs'
$builtinsSource = Join-Path $library 'compiler-builtins\compiler-builtins\src\lib.rs'
if (-not (Test-Path -LiteralPath $coreSource)) { throw "rustc source missing: $coreSource" }
if (-not (Test-Path -LiteralPath $builtinsSource)) { throw "rustc source missing: $builtinsSource" }

$core = Join-Path $OutputDirectory 'libcore.rmeta'
$builtins = Join-Path $OutputDirectory 'libcompiler_builtins.rmeta'
$hal = Join-Path $OutputDirectory 'libf28035_safe_hal.rmeta'
$case1 = Join-Path $OutputDirectory 'libcase1.rmeta'
$common = @('--edition=2024', '--target=c28x-none-elf', '--crate-type=lib',
    '--emit=metadata', '-Cpanic=abort', '-Awarnings')

function Check-Compile([string]$Name, [string[]]$Arguments, [string]$Output) {
    $result = Invoke-NativeCapture $Rustc $Arguments
    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Output)) {
        throw "$Name target metadata failed: $($result.StdOut)`n$($result.StdErr)"
    }
}

Check-Compile 'core' (@($common) + @('--crate-name=core', '-Zforce-unstable-if-unmarked',
    '-o', $core, $coreSource)) $core
Check-Compile 'compiler_builtins' (@($common) + @('--crate-name=compiler_builtins',
    '-Zforce-unstable-if-unmarked', '--cfg', 'feature="compiler-builtins"',
    '--extern', "core=$core", '-o', $builtins, $builtinsSource)) $builtins
Check-Compile 'Safe HAL' (@($common) + @('--crate-name=f28035_safe_hal',
    '--extern', "core=$core", '--extern', "compiler_builtins=$builtins",
    '-L', "dependency=$OutputDirectory", '-o', $hal,
    (Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs'))) $hal
Check-Compile 'case1' (@($common) + @('--crate-name=case1',
    '--extern', "core=$core", '--extern', "compiler_builtins=$builtins",
    '--extern', "f28035_safe_hal=$hal", '-L', "dependency=$OutputDirectory",
    '-o', $case1, $Case1Source)) $case1

Write-Output "C28x core metadata: $core"
Write-Output "C28x Safe HAL metadata: $hal"
Write-Output "C28x case1 metadata: $case1"
Write-Output 'PASS: target rustc type-checked core, Safe HAL, and case1 (metadata only).'
