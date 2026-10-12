# Compile Rust for the patched C28x target, then link its object with TI C.
param(
    [string]$Rustc = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $Rustc) { $Rustc = $env:C28X_RUSTC }
if (-not $Rustc) {
    $Rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
}
if (-not (Test-Path -LiteralPath $Rustc)) {
    throw "Patched C28x rustc is missing: $Rustc"
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root 'build\rustc-c28x-smoke'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$source = Join-Path $root 'backend\llvm-c28x\test\Rust\smoke-no-core.rs'
$ir = Join-Path $OutputDirectory 'rust_id.ll'
$obj = Join-Path $OutputDirectory 'rust_id.obj'
$callerSource = Join-Path $OutputDirectory 'call_rust.c'
$callerObject = Join-Path $OutputDirectory 'call_rust.obj'
$output = Join-Path $OutputDirectory 'call_rust.out'
$map = Join-Path $OutputDirectory 'call_rust.map'
$ramCommand = Join-Path $root 'tools\F28035_ram.cmd'
$sectionsCommand = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

$compile = Invoke-NativeCapture $Rustc @('--edition=2024', '--target=c28x-none-elf',
    '--crate-name=c28x_smoke', '--crate-type=lib', '-Cpanic=abort', '-Copt-level=2',
    "--emit=llvm-ir=$ir,obj=$obj", $source)
if ($compile.ExitCode -ne 0) {
    throw "C28x rustc failed: $($compile.StdOut)`n$($compile.StdErr)"
}
if (-not (Test-Path -LiteralPath $ir) -or -not (Test-Path -LiteralPath $obj)) {
    throw 'C28x rustc did not emit both LLVM IR and object'
}
$irText = Get-Content -Raw -LiteralPath $ir
if ($irText -notmatch 'target triple = "c28x-ti-none"') {
    throw 'rustc IR was not compiled for the C28x target'
}
if ($irText -notmatch 'target datalayout = "e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16"') {
    throw 'rustc IR does not use the frozen C28x data layout'
}

$inspect = Invoke-NativeCapture $C28xToolchain.Ofd2000 @('-x', $obj)
if ($inspect.ExitCode -ne 0 -or $inspect.StdOut -notmatch '<e_machine>EM_TI_C2000</e_machine>') {
    throw "TI ofd2000 rejected the Rust object: $($inspect.StdErr)"
}

[IO.File]::WriteAllText($callerSource,
    "extern unsigned int rust_id(unsigned int);`nunsigned int call_rust(void) { return rust_id(3U); }`n")
$cCompile = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--compile_only',
    "--output_file=$callerObject", $callerSource)
if ($cCompile.ExitCode -ne 0) {
    throw "TI C caller compilation failed: $($cCompile.StdOut)`n$($cCompile.StdErr)"
}
$link = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--run_linker', '--entry_point=call_rust',
    '--ram_model', "--map_file=$map", "--output_file=$output",
    $callerObject, $obj, $ramCommand, $sectionsCommand)
if ($link.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "TI linker rejected Rust object: $($link.StdOut)`n$($link.StdErr)"
}

Write-Output "C28x Rust IR: $ir"
Write-Output "C28x Rust object: $obj"
Write-Output "TI linked output: $output"
Write-Output 'PASS: target rustc directly emitted C28x IR and object; TI C caller linked.'
