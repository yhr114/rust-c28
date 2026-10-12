param(
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\native-rust-add'
$rustSource = Join-Path $projectRoot 'crates\rust-api\src\arithmetic.rs'
$generatedAssembly = Join-Path $outputDirectory 'rust_add_from_rs.asm'
$harnessSource = Join-Path $projectRoot 'platform\firmware\rust_add_test.c'
$startupSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source\DSP2803x_CodeStartBranch.asm'
$linkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\cmd\F28035.cmd'
$eabiSections = Join-Path $projectRoot 'platform\firmware\F28035_EABI_sections.cmd'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_fpu32_eabi.lib'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$rustObject = Join-Path $outputDirectory 'rust_add_from_rs.obj'
$harnessObject = Join-Path $outputDirectory 'rust_add_test.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$firmwareOut = Join-Path $outputDirectory 'native_rust_add_test.out'
$firmwareHex = Join-Path $outputDirectory 'native_rust_add_test.hex'
$mapFile = Join-Path $outputDirectory 'native_rust_add_test.map'

foreach ($tool in @($Compiler, $Cargo, $hexConverter)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Push-Location (Join-Path $projectRoot 'crates\rust-api')
try {
    & $Cargo test
    if ($LASTEXITCODE -ne 0) { throw 'Rust source tests failed.' }
}
finally {
    Pop-Location
}

& $Cargo test --manifest-path (Join-Path $PSScriptRoot 'rust-to-ti-c\Cargo.toml')
if ($LASTEXITCODE -ne 0) { throw 'Native subset backend tests failed.' }

& (Join-Path $PSScriptRoot 'rust-to-ti-asm.ps1') `
    -InputFile $rustSource `
    -OutputFile $generatedAssembly `
    -Cargo $Cargo

$commonOptions = @(
    '--silicon_version=28',
    '--float_support=fpu32',
    '--abi=eabi',
    '--compile_only'
)

& $Compiler @commonOptions --output_file=$rustObject $generatedAssembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble Rust-generated C28x assembly.' }

& $Compiler @commonOptions --opt_level=2 --include_path=$compilerInclude --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile native Rust test harness.' }

& $Compiler @commonOptions --output_file=$startupObject $startupSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile startup code.' }

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
    throw "Native Rust C28x link failed with exit code $LASTEXITCODE"
}

& $hexConverter --intel --byte --memwidth=16 --romwidth=16 --outfile=$firmwareHex $firmwareOut
if ($LASTEXITCODE -ne 0) { throw 'hex2000 failed.' }

Write-Output "Rust  $rustSource"
Write-Output "Asm   $generatedAssembly"
Write-Output "Obj   $rustObject"
Write-Output "Out   $firmwareOut"
Write-Output "Hex   $firmwareHex"
Write-Output "Map   $mapFile"
