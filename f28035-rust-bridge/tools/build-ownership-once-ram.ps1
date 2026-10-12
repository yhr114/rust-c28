#Requires -Version 5.1
param([string]$Compiler = '', [string]$Cargo = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'build\ownership-gpio34'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$mir = Join-Path $out 'ownership.mir.txt'
$asm = Join-Path $out 'ownership.asm'
$rustObj = Join-Path $out 'ownership.obj'
$startObj = Join-Path $out 'start.obj'
$firmware = Join-Path $out 'ownership_once_ram.out'
$map = Join-Path $out 'ownership_once_ram.map'

& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile (Join-Path $root 'crates\ownership-gpio34\src\lib.rs') `
    -OutputFile $mir -AssemblyFile $asm -Cargo $Cargo `
    -OnlyExport 'rust_once_acquire,rust_ownership_application,rust_gpio34_set_low' `
    -RustcArguments '-Zmir-opt-level=4'
if ($LASTEXITCODE -ne 0) { throw 'Rust ownership MIR lowering failed.' }
if (-not (Select-String -Path $mir -Pattern 'c28x-codegen: emitted rust_once_acquire' -Quiet)) {
    throw 'Rust ownership method was not emitted.'
}
if (-not (Select-String -Path $mir -Pattern 'c28x-codegen: emitted rust_ownership_application' -Quiet)) {
    throw 'Rust ownership application was not emitted.'
}
if (-not (Select-String -Path $mir -Pattern 'c28x-codegen: emitted rust_gpio34_set_low' -Quiet)) {
    throw 'Rust GPIO34 output method was not emitted.'
}
$asmText = Get-Content -LiteralPath $asm -Raw
if ($asmText -match '(?m)^\s*\.ref\s' -or $asmText -notmatch 'rust_once_acquire:' -or
    $asmText -notmatch 'rust_ownership_application:' -or
    $asmText -notmatch 'rust_gpio34_set_low:') {
    throw 'Ownership assembly has an unresolved reference or missing Rust function.'
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$rustObj" $asm
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble Rust ownership method.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$startObj" (Join-Path $root 'platform\runtime\ownership_once_ram_start.asm')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble ownership startup.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --stack_size=0x100 --unused_section_elimination=on `
        "--map_file=$map" "--output_file=$firmware" $startObj $rustObj `
        (Join-Path $PSScriptRoot 'F28035_ram.cmd') `
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')
    if ($LASTEXITCODE -ne 0) { throw 'Zero-C ownership RAM link failed.' }
} finally {
    $ErrorActionPreference = $previousPreference
}

$mapText = Get-Content -LiteralPath $map -Raw
if ($mapText -match '(?i)\.lib|f28035_bridge|sysctrl\.obj|gpio\.obj|main\.obj' -or
    $mapText -notmatch 'ownership\.obj' -or $mapText -notmatch 'start\.obj') {
    throw 'Unexpected C object or library in ownership link map.'
}
Write-Output "ZERO_C_OWNERSHIP_LINK=PASS $firmware"
