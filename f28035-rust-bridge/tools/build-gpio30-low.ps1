param(
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\standalone-image-keys.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\gpio30-low'
$generatedDirectory = Join-Path $outputDirectory 'generated'
$rustSource = Join-Path $projectRoot 'crates\rust-targets\gpio30_low.rs'
$generatedC = Join-Path $generatedDirectory 'gpio30_low.c'
$harnessSource = Join-Path $projectRoot 'platform\firmware\gpio30_low_test.c'
$startupSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source\DSP2803x_CodeStartBranch.asm'
$globalDefinitionsSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\source\DSP2803x_GlobalVariableDefs.c'
$headers = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\include'
$linkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\cmd\F28035.cmd'
$headerLinkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$eabiSections = Join-Path $projectRoot 'platform\firmware\F28035_EABI_sections.cmd'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_fpu32_eabi.lib'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$rustObject = Join-Path $outputDirectory 'gpio30_low.obj'
$rustAssembly = Join-Path $outputDirectory 'gpio30_low.asm'
$rustListing = Join-Path $outputDirectory 'gpio30_low.lst'
$harnessObject = Join-Path $outputDirectory 'gpio30_low_test.obj'
$globalDefinitionsObject = Join-Path $outputDirectory 'global_variable_defs.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$bridgeObject = Join-Path $projectRoot 'build\c28x\f28035_bridge.obj'
$firmwareOut = Join-Path $outputDirectory 'gpio30_low_test.out'
$firmwareHex = Join-Path $outputDirectory 'gpio30_low_test.hex'
$mapFile = Join-Path $outputDirectory 'gpio30_low_test.map'

foreach ($tool in @($Compiler, $Cargo, $hexConverter)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}

New-Item -ItemType Directory -Path $generatedDirectory -Force | Out-Null

& (Join-Path $PSScriptRoot 'build-c-bridge.ps1') -Compiler $Compiler
if ($LASTEXITCODE -ne 0) {
    throw "C bridge build failed with exit code $LASTEXITCODE"
}

$rustToTiCManifest = Join-Path $PSScriptRoot 'rust-to-ti-c\Cargo.toml'
$rustToTiCTarget = Join-Path $PSScriptRoot 'rust-to-ti-c\target-host'
Push-Location (Split-Path -Parent $projectRoot)
try {
    & $Toolchain.HostTestCargo test --manifest-path $rustToTiCManifest --target $Toolchain.HostTestTarget --target-dir $rustToTiCTarget
    if ($LASTEXITCODE -ne 0) {
        throw "rust-to-ti-c tests failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot 'rust-to-ti-c.ps1') -InputFile $rustSource -OutputFile $generatedC -Cargo $Cargo

$compileOptions = @(
    '--silicon_version=28',
    '--float_support=fpu32',
    '--abi=eabi',
    '--compile_only',
    '--opt_level=2',
    '--gen_func_subsections=on',
    '--symdebug:dwarf',
    "--include_path=$compilerInclude",
    "--include_path=$headers",
    "--include_path=$common"
)

& $Compiler @compileOptions --keep_asm --asm_listing --output_file=$rustObject $generatedC
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile generated GPIO30 code.' }

$compilerAssembly = Join-Path $projectRoot 'gpio30_low.asm'
$compilerListing = Join-Path $projectRoot 'gpio30_low.lst'
if (Test-Path -LiteralPath $compilerAssembly) {
    Move-Item -LiteralPath $compilerAssembly -Destination $rustAssembly -Force
}
if (Test-Path -LiteralPath $compilerListing) {
    Move-Item -LiteralPath $compilerListing -Destination $rustListing -Force
}

& $Compiler @compileOptions --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO30 harness.' }

& $Compiler @compileOptions --output_file=$globalDefinitionsObject $globalDefinitionsSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile TI global register definitions.' }

& $Compiler @compileOptions --output_file=$startupObject $startupSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile TI startup code.' }

& $Compiler `
    --silicon_version=28 `
    --float_support=fpu32 `
    --abi=eabi `
    --run_linker `
    --entry_point=code_start `
    --rom_model `
    --stack_size=0x100 `
    --unused_section_elimination=on `
    --warn_sections `
    --map_file=$mapFile `
    --output_file=$firmwareOut `
    $startupObject `
    $harnessObject `
    $rustObject `
    $bridgeObject `
    $globalDefinitionsObject `
    $linkerCommand `
    $eabiSections `
    $headerLinkerCommand `
    $runtimeLibrary

if ($LASTEXITCODE -ne 0) {
    throw "GPIO30 firmware link failed with exit code $LASTEXITCODE"
}

& $hexConverter --intel --byte --memwidth=16 --romwidth=16 --outfile=$firmwareHex $firmwareOut
if ($LASTEXITCODE -ne 0) {
    throw "hex2000 failed with exit code $LASTEXITCODE"
}

Write-Output "Built $firmwareOut"
Write-Output "Hex   $firmwareHex"
Write-Output "Map   $mapFile"
Write-Output "Asm   $rustAssembly"

# 新鲜度戳：链接+hex 成功后记录输入指纹，flash-and-verify-gpio30-low.ps1 上板前断言
Set-ImageStamp -Image $firmwareOut -Key (Get-GpioTargetImageKey -Compiler $Compiler -ProjectRoot $projectRoot -Target gpio30)
