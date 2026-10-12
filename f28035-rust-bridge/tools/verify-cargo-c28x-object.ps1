# Cargo -> patched rustc -> C28x object -> TI link smoke test.
param(
    [string]$Rustc = '',
    [string]$Cargo = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $Rustc) { $Rustc = $env:C28X_RUSTC }
if (-not $Rustc) { $Rustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe' }
if (-not $Cargo) { $Cargo = 'D:\c28x-toolchain\rustup-gnu\toolchains\nightly-2026-09-14-x86_64-pc-windows-gnu\bin\cargo.exe' }
if (-not (Test-Path -LiteralPath $Rustc)) { throw "C28x rustc not found: $Rustc" }
if (-not (Test-Path -LiteralPath $Cargo)) { throw "Cargo not found: $Cargo" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'build\cargo-c28x-smoke' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$env:RUSTC = $Rustc
$env:CARGO_TARGET_DIR = $OutputDirectory
$manifest = Join-Path $root 'backend\llvm-c28x\test\Cargo\direct-obj-smoke\Cargo.toml'
$build = Invoke-NativeCapture $Cargo @('rustc', '--manifest-path', $manifest,
    '--lib', '--target', 'c28x-none-elf', '--release', '--', '--emit=obj,llvm-ir')
if ($build.ExitCode -ne 0) {
    throw "Cargo C28x build failed: $($build.StdOut)`n$($build.StdErr)"
}

$objects = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Filter 'c28x_direct_obj_smoke-*.o' |
    Sort-Object LastWriteTimeUtc -Descending)
if ($objects.Count -eq 0) { throw 'Cargo did not produce a C28x object' }
$obj = $objects[0].FullName
$ir = [IO.Path]::ChangeExtension($obj, '.ll')
if (-not (Test-Path -LiteralPath $ir)) { throw 'Cargo did not produce C28x LLVM IR' }
$irText = Get-Content -Raw -LiteralPath $ir
if ($irText -notmatch 'target triple = "c28x-ti-none"') {
    throw 'Cargo used the wrong target triple'
}

$inspect = Invoke-NativeCapture $C28xToolchain.Ofd2000 @('-x', $obj)
if ($inspect.ExitCode -ne 0 -or $inspect.StdOut -notmatch '<e_machine>EM_TI_C2000</e_machine>') {
    throw "TI ofd2000 rejected Cargo's object: $($inspect.StdErr)"
}

$callerSource = Join-Path $OutputDirectory 'cargo_call_rust.c'
$callerObject = Join-Path $OutputDirectory 'cargo_call_rust.obj'
$output = Join-Path $OutputDirectory 'cargo_call_rust.out'
[IO.File]::WriteAllText($callerSource,
    "extern unsigned int rust_id(unsigned int);`nunsigned int call_rust(void) { return rust_id(3U); }`n")
$compile = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--compile_only',
    "--output_file=$callerObject", $callerSource)
if ($compile.ExitCode -ne 0) {
    throw "TI C caller failed: $($compile.StdOut)`n$($compile.StdErr)"
}
$link = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--silicon_version=28',
    '--float_support=softlib', '--abi=eabi', '--run_linker', '--entry_point=call_rust',
    '--ram_model', "--output_file=$output", $callerObject, $obj,
    (Join-Path $root 'tools\F28035_ram.cmd'),
    (Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'))
if ($link.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "TI linker rejected Cargo's object: $($link.StdOut)`n$($link.StdErr)"
}

Write-Output "Cargo object: $obj"
Write-Output "TI linked output: $output"
Write-Output 'PASS: Cargo drove patched rustc to C28x object and TI linked it with a C caller.'
