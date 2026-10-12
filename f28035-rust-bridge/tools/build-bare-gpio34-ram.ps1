#Requires -Version 5.1
param([string]$Compiler = '', [string]$Cargo = '', [switch]$SafeHal)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = if ($SafeHal) { Join-Path $root 'build\safe-gpio34' } else { Join-Path $root 'build\bare-gpio34' }
$source = if ($SafeHal) { Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs' } else { Join-Path $root 'crates\bare-gpio34\src\lib.rs' }
$entry = if ($SafeHal) { 'rust_safe_gpio34_low' } else { 'rust_bare_gpio34_low' }
$startupSource = if ($SafeHal) { 'safe_gpio34_ram_start.asm' } else { 'bare_gpio34_ram_start.asm' }
$mir = Join-Path $outDir 'bare.mir.txt'
$asm = Join-Path $outDir 'bare.asm'
$rustObj = Join-Path $outDir 'bare.obj'
$startObj = Join-Path $outDir 'start.obj'
$firmware = Join-Path $outDir $(if ($SafeHal) { 'safe_gpio34_ram.out' } else { 'bare_gpio34_ram.out' })
$map = Join-Path $outDir $(if ($SafeHal) { 'safe_gpio34_ram.map' } else { 'bare_gpio34_ram.map' })
foreach ($path in @($Compiler, $Cargo, $source)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $path" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if ($SafeHal) {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $source -OutputFile $mir `
        -AssemblyFile $asm -Cargo $Cargo -OnlyExport $entry `
        -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature="bare-mmio"')
} else {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $source -OutputFile $mir `
        -AssemblyFile $asm -Cargo $Cargo -RustcArguments '-Zmir-opt-level=4'
}
if ($LASTEXITCODE -ne 0) { throw 'Rust MIR lowering failed.' }
if (-not (Select-String -Path $mir -Pattern "c28x-codegen: emitted $entry" -Quiet)) {
    throw 'Rust entry was not emitted by the MIR backend.'
}
$asmText = Get-Content -LiteralPath $asm -Raw
if ($asmText -match '(?m)^\s*\.ref\s' -or $asmText -notmatch "${entry}:") {
    throw 'Generated Rust assembly has unresolved external references or no entry.'
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$rustObj" $asm
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble Rust MIR output.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$startObj" (Join-Path $root "platform\runtime\$startupSource")
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble RAM startup.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --stack_size=0x100 --unused_section_elimination=on `
        "--map_file=$map" "--output_file=$firmware" `
        $startObj $rustObj (Join-Path $PSScriptRoot 'F28035_ram.cmd') `
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')
    if ($LASTEXITCODE -ne 0) { throw 'Zero-C RAM link failed.' }
} finally {
    $ErrorActionPreference = $previousPreference
}
if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) { throw 'Firmware output missing.' }
$mapText = Get-Content -LiteralPath $map -Raw
if ($mapText -match '(?i)\.lib|f28035_bridge|sysctrl\.obj|gpio\.obj|main\.obj' -or
    $mapText -notmatch 'bare\.obj' -or $mapText -notmatch 'start\.obj') {
    throw 'Unexpected object or library in link map.'
}
if ($SafeHal) { Write-Output "ZERO_C_SAFE_HAL_LINK=PASS $firmware" }
else { Write-Output "ZERO_C_LINK=PASS $firmware" }
Write-Output "MAP $map"
