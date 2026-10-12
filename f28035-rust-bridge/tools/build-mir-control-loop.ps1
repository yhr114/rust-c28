param(
    [string]$Compiler = '',
    [string]$Cargo = '',
    [ValidateSet('softlib')]
    [string]$FloatSupport = 'softlib'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\mir-control-loop'
$mirDirectory = Join-Path $projectRoot 'build\mir'
$rustSource = Join-Path $projectRoot 'crates\rust-api\src\lib.rs'
$mirOutput = Join-Path $mirDirectory 'control-loop.mir.txt'
$assembly = Join-Path $mirDirectory 'control-loop.asm'
$rustObject = Join-Path $outputDirectory 'rust_control_loop.obj'
$mainObject = Join-Path $outputDirectory 'main.obj'
$bridgeObject = Join-Path $projectRoot 'build\c28x\f28035_bridge.obj'
$sysCtrlObject = Join-Path $outputDirectory 'sysctrl.obj'
$gpioObject = Join-Path $outputDirectory 'gpio.obj'
$delayObject = Join-Path $outputDirectory 'delay.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$firmwareOut = Join-Path $outputDirectory 'rust_control_loop.out'
$firmwareHex = Join-Path $outputDirectory 'rust_control_loop.hex'
$mapFile = Join-Path $outputDirectory 'rust_control_loop.map'
$headers = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\include'
$commonSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$linkerCommand = Join-Path $projectRoot 'tools\F28035_ram.cmd'
$headerLinkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$eabiSections = Join-Path $projectRoot 'tools\F28035_EABI_sections_ram.cmd'
$peripheralSymbols = Join-Path $projectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'

foreach ($tool in @($Compiler, $Cargo, $hexConverter)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required tool not found: $tool"
    }
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

& (Join-Path $PSScriptRoot 'build-c-bridge.ps1') -Compiler $Compiler -FloatSupport $FloatSupport
if ($LASTEXITCODE -ne 0) { throw 'C bridge build failed.' }
& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile $rustSource -OutputFile $mirOutput -AssemblyFile $assembly -Cargo $Cargo `
    -RustcArguments '-Zmir-opt-level=4'
if ($LASTEXITCODE -ne 0) { throw 'Control-loop MIR lowering failed.' }

$commonOptions = @(
    '--silicon_version=28',
    "--float_support=$FloatSupport",
    '--abi=eabi',
    '--compile_only',
    '--gen_func_subsections=on',
    "--include_path=$compilerInclude",
    "--include_path=$headers",
    "--include_path=$common"
)

& $Compiler @commonOptions --output_file=$rustObject $assembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble MIR control loop.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$mainObject (Join-Path $projectRoot 'platform\firmware\main.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile firmware entry.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$sysCtrlObject (Join-Path $commonSource 'DSP2803x_SysCtrl.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile system initialization.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$gpioObject (Join-Path $commonSource 'DSP2803x_Gpio.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO initialization.' }
& $Compiler @commonOptions --output_file=$delayObject (Join-Path $projectRoot 'platform\runtime\c28x_us_delay_eabi.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble delay helper.' }
& $Compiler @commonOptions --output_file=$startupObject (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile startup.' }

& $Compiler `
    --silicon_version=28 --float_support=$FloatSupport --abi=eabi --run_linker `
    --entry_point=code_start --rom_model --stack_size=0x100 `
    --unused_section_elimination=on --warn_sections `
    --map_file=$mapFile --output_file=$firmwareOut `
    $startupObject $mainObject $rustObject $bridgeObject $sysCtrlObject $gpioObject `
    $delayObject $linkerCommand $eabiSections $peripheralSymbols `
    $headerLinkerCommand $runtimeLibrary
if ($LASTEXITCODE -ne 0) { throw 'Failed to link MIR control-loop firmware.' }

$peripheralCinit = Select-String -Path $mapFile -Pattern '\.cinit\..*(RegsFile|AdcResultFile|PieVectTableFile)\.load'
if ($peripheralCinit) {
    throw "EABI startup would initialize live peripheral registers: $($peripheralCinit.Line -join ', ')"
}

& $hexConverter --intel --byte --memwidth=16 --romwidth=16 --outfile=$firmwareHex $firmwareOut
if ($LASTEXITCODE -ne 0) { throw 'hex2000 failed.' }

Write-Output "Rust $rustSource"
Write-Output "MIR  $mirOutput"
Write-Output "Asm  $assembly"
Write-Output "Out  $firmwareOut"
Write-Output "Hex  $firmwareHex"
