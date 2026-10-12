# Verify that a directly emitted C28x ELF object is accepted by the TI linker.
# This is an LLVM IR -> object integration check, not a Rust -> object build.
# Usage: powershell -File tools\verify-llvm-ti-object.ps1
param(
    [string]$LlvmBin = '',
    [string]$Compiler = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$root = Split-Path -Parent $PSScriptRoot
if (-not $LlvmBin) { $LlvmBin = Join-Path $C28xToolchain.Build 'bin' }
if (-not $Compiler) { $Compiler = $C28xToolchain.Cl2000 }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'build\llvm-direct-obj' }

$llc = Join-Path $LlvmBin 'llc.exe'
$ofd = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'
$source = Join-Path $root 'backend\llvm-c28x\test\CodeGen\const3.ll'
$ramCommand = Join-Path $root 'tools\F28035_ram.cmd'
$sectionsCommand = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'
foreach ($input in @($llc, $Compiler, $ofd, $source, $ramCommand, $sectionsCommand)) {
    if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "Required input missing: $input" }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$object = Join-Path $OutputDirectory 'const3.obj'
$output = Join-Path $OutputDirectory 'const3.out'
$map = Join-Path $OutputDirectory 'const3.map'

$emit = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
    '-filetype=obj', $source, '-o', $object)
if ($emit.ExitCode -ne 0) { throw "LLVM object emission failed: $($emit.StdErr)" }

$inspect = Invoke-NativeCapture $ofd @('-x', $object)
if ($inspect.ExitCode -ne 0 -or $inspect.StdOut -notmatch '<e_machine>EM_TI_C2000</e_machine>') {
    throw "TI ofd2000 did not recognize a C2000 ELF object: $($inspect.StdErr)"
}

$link = Invoke-NativeCapture $Compiler @('--silicon_version=28', '--float_support=softlib',
    '--abi=eabi', '--run_linker', '--entry_point=const3', '--ram_model',
    "--map_file=$map", "--output_file=$output", $object, $ramCommand, $sectionsCommand)
if ($link.ExitCode -ne 0) { throw "TI linker rejected LLVM object: $($link.StdOut)`n$($link.StdErr)" }
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw "TI output missing: $output" }

$mapText = Get-Content -Raw -LiteralPath $map
if ($mapText -notmatch 'ENTRY POINT SYMBOL:\s*"const3"\s+address:\s*00008000') {
    throw "TI map does not place const3 at the RAM entry address: $map"
}

$callerSource = Join-Path $OutputDirectory 'call_const3.c'
$callerObject = Join-Path $OutputDirectory 'call_const3.obj'
$mixedOutput = Join-Path $OutputDirectory 'call_const3.out'
$mixedMap = Join-Path $OutputDirectory 'call_const3.map'
[System.IO.File]::WriteAllText($callerSource,
    "extern unsigned int const3(void);`nunsigned int call_const3(void) { return const3(); }`n")
$compile = Invoke-NativeCapture $Compiler @('--silicon_version=28', '--float_support=softlib',
    '--abi=eabi', '--compile_only', "--output_file=$callerObject", $callerSource)
if ($compile.ExitCode -ne 0) { throw "TI C caller compilation failed: $($compile.StdOut)`n$($compile.StdErr)" }
$mixedLink = Invoke-NativeCapture $Compiler @('--silicon_version=28', '--float_support=softlib',
    '--abi=eabi', '--run_linker', '--entry_point=call_const3', '--ram_model',
    "--map_file=$mixedMap", "--output_file=$mixedOutput", $callerObject, $object,
    $ramCommand, $sectionsCommand)
if ($mixedLink.ExitCode -ne 0) {
    throw "TI C caller cannot link the LLVM object: $($mixedLink.StdOut)`n$($mixedLink.StdErr)"
}
if (-not (Test-Path -LiteralPath $mixedOutput -PathType Leaf)) {
    throw "Mixed C/LLVM output missing: $mixedOutput"
}

Write-Output "LLVM object: $object"
Write-Output "TI linked output: $output"
Write-Output "TI C caller linked output: $mixedOutput"
Write-Output 'PASS: LLVM emitted a C28x object directly; the TI EABI linker accepted it and a TI C caller.'
