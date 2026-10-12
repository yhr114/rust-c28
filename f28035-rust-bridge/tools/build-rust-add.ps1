param(
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\rust-add'
$generatedDirectory = Join-Path $outputDirectory 'generated'
$rustSource = Join-Path $projectRoot 'crates\rust-api\src\arithmetic.rs'
$generatedC = Join-Path $generatedDirectory 'rust_add.c'
$harnessSource = Join-Path $projectRoot 'platform\firmware\rust_add_test.c'
$startupSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source\DSP2803x_CodeStartBranch.asm'
$linkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\cmd\F28035.cmd'
$eabiSections = Join-Path $projectRoot 'platform\firmware\F28035_EABI_sections.cmd'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path (Split-Path -Parent $Compiler) '..\lib\rts2800_fpu32_eabi.lib'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$rustObject = Join-Path $outputDirectory 'rust_add.obj'
$harnessObject = Join-Path $outputDirectory 'rust_add_test.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$assemblyListing = Join-Path $outputDirectory 'rust_add.asm'
$mixedListing = Join-Path $outputDirectory 'rust_add.lst'
$firmwareOut = Join-Path $outputDirectory 'rust_add_test.out'
$firmwareHex = Join-Path $outputDirectory 'rust_add_test.hex'
$mapFile = Join-Path $outputDirectory 'rust_add_test.map'

foreach ($tool in @($Compiler, $Cargo, $hexConverter)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}

if (-not (Test-Path -LiteralPath $runtimeLibrary)) {
    throw "TI EABI runtime library not found: $runtimeLibrary"
}

New-Item -ItemType Directory -Path $generatedDirectory -Force | Out-Null

Push-Location (Join-Path $projectRoot 'crates\rust-api')
try {
    & $Cargo test
    if ($LASTEXITCODE -ne 0) {
        throw "cargo test failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

& $Cargo test --manifest-path (Join-Path $PSScriptRoot 'rust-to-ti-c\Cargo.toml')
if ($LASTEXITCODE -ne 0) {
    throw "rust-to-ti-c tests failed with exit code $LASTEXITCODE"
}

& (Join-Path $PSScriptRoot 'rust-to-ti-c.ps1') -InputFile $rustSource -OutputFile $generatedC

$compileOptions = @(
    '--silicon_version=28',
    '--float_support=fpu32',
    '--abi=eabi',
    '--compile_only',
    '--opt_level=2',
    '--symdebug:dwarf',
    "--include_path=$compilerInclude"
)

& $Compiler @compileOptions --keep_asm --asm_listing --output_file=$rustObject $generatedC
if ($LASTEXITCODE -ne 0) {
    throw "cl2000 failed while compiling generated Rust C with exit code $LASTEXITCODE"
}

$compilerAssembly = Join-Path $projectRoot 'rust_add.asm'
$compilerListing = Join-Path $projectRoot 'rust_add.lst'
if (Test-Path -LiteralPath $compilerAssembly) {
    Move-Item -LiteralPath $compilerAssembly -Destination $assemblyListing -Force
}
if (Test-Path -LiteralPath $compilerListing) {
    Move-Item -LiteralPath $compilerListing -Destination $mixedListing -Force
}

& $Compiler @compileOptions --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) {
    throw "cl2000 failed while compiling the C harness with exit code $LASTEXITCODE"
}

& $Compiler @compileOptions --output_file=$startupObject $startupSource
if ($LASTEXITCODE -ne 0) {
    throw "cl2000 failed while compiling startup code with exit code $LASTEXITCODE"
}

& $Compiler `
    --silicon_version=28 `
    --float_support=fpu32 `
    --abi=eabi `
    --run_linker `
    --entry_point=code_start `
    --rom_model `
    --stack_size=0x100 `
    --warn_sections `
    --map_file=$mapFile `
    --output_file=$firmwareOut `
    $startupObject `
    $harnessObject `
    $rustObject `
    $linkerCommand `
    $eabiSections `
    $runtimeLibrary

if ($LASTEXITCODE -ne 0) {
    throw "C28x link failed with exit code $LASTEXITCODE"
}

& $hexConverter `
    --intel `
    --byte `
    --memwidth=16 `
    --romwidth=16 `
    --outfile=$firmwareHex `
    $firmwareOut

if ($LASTEXITCODE -ne 0) {
    throw "hex2000 failed with exit code $LASTEXITCODE"
}

Write-Output "Built $firmwareOut"
Write-Output "Hex   $firmwareHex"
Write-Output "Map   $mapFile"
Write-Output "Asm   $assemblyListing"
