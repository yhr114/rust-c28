param(
    [Parameter(Mandatory = $true)]
    [string]$Case,

    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$dependencyRoot = $projectRoot
$caseParts = $Case.Replace('/', '\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
if ($caseParts.Count -ne 2) {
    throw 'Case must use category/name, for example gpio/gpio_output_basic'
}

$category = $caseParts[0]
$name = $caseParts[1]
$caseRoot = Join-Path $projectRoot "app\hardware-tests\$category\$name"
$rustSource = Join-Path $caseRoot 'src\main.rs'
$caseManifest = Join-Path $caseRoot 'case.toml'
if (-not (Test-Path -LiteralPath $rustSource -PathType Leaf)) {
    throw "Rust case entry not found: $rustSource"
}
if (-not (Test-Path -LiteralPath $caseManifest -PathType Leaf)) {
    throw "Case manifest not found: $caseManifest"
}

$translatorManifest = Join-Path $dependencyRoot 'tools\rust-to-ti-c\Cargo.toml'
$vendorRoot = Join-Path $dependencyRoot 'platform\vendor\ti\f2803x'
$headers = Join-Path $vendorRoot 'headers\include'
$common = Join-Path $vendorRoot 'common\include'
$commonSource = Join-Path $vendorRoot 'common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$linkerCommand = Join-Path $vendorRoot 'common\cmd\F28035.cmd'
$headerLinkerCommand = Join-Path $vendorRoot 'headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$eabiSections = Join-Path $dependencyRoot 'platform\firmware\F28035_EABI_sections.cmd'
$peripheralSymbols = Join-Path $dependencyRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'
$outputDirectory = Join-Path $projectRoot "build\$category\$name"

foreach ($path in @($Compiler, $Cargo, $translatorManifest, $runtimeLibrary, $linkerCommand)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required build input not found: $path"
    }
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$generatedC = Join-Path $outputDirectory 'rust_case.generated.c'
$caseObject = Join-Path $outputDirectory 'rust_case.obj'
$bridgeObject = Join-Path $outputDirectory 'f28035_bridge.obj'
$mainObject = Join-Path $outputDirectory 'main.obj'
$defaultInterruptsObject = Join-Path $outputDirectory 'default_interrupts.obj'
$sysCtrlObject = Join-Path $outputDirectory 'sysctrl.obj'
$gpioObject = Join-Path $outputDirectory 'gpio.obj'
$delayObject = Join-Path $outputDirectory 'delay.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$firmwareOut = Join-Path $outputDirectory "$name.out"
$mapFile = Join-Path $outputDirectory "$name.map"

$previousTarget = $env:CARGO_BUILD_TARGET
try {
    $env:CARGO_BUILD_TARGET = 'x86_64-pc-windows-msvc'
    & $Cargo run --quiet --manifest-path $translatorManifest -- $rustSource $generatedC
    if ($LASTEXITCODE -ne 0) { throw 'Rust case translation failed.' }
} finally {
    $env:CARGO_BUILD_TARGET = $previousTarget
}

$commonOptions = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
    '--compile_only', '--gen_func_subsections=on',
    "--include_path=$compilerInclude", "--include_path=$headers", "--include_path=$common",
    "--include_path=$(Join-Path $projectRoot 'sdk\c-abi')"
)

& $Compiler @commonOptions --opt_level=2 --output_file=$caseObject $generatedC
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile generated case C.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$bridgeObject (Join-Path $projectRoot 'sdk\c-abi\f28035_bridge.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile C ABI bridge.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$mainObject (Join-Path $projectRoot 'app\firmware\main.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile firmware entry.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$defaultInterruptsObject (Join-Path $projectRoot 'app\firmware\default_interrupts.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile default interrupt callbacks.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$sysCtrlObject (Join-Path $commonSource 'DSP2803x_SysCtrl.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile system initialization.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$gpioObject (Join-Path $commonSource 'DSP2803x_Gpio.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO initialization.' }
& $Compiler @commonOptions --output_file=$delayObject (Join-Path $dependencyRoot 'platform\runtime\c28x_us_delay_eabi.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble delay helper.' }
& $Compiler @commonOptions --output_file=$startupObject (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble startup.' }

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --rom_model --stack_size=0x100 `
        --unused_section_elimination=on --warn_sections `
        --map_file=$mapFile --output_file=$firmwareOut `
        $startupObject $mainObject $defaultInterruptsObject $caseObject $bridgeObject $sysCtrlObject $gpioObject `
        $delayObject $linkerCommand $eabiSections $peripheralSymbols `
        $headerLinkerCommand $runtimeLibrary 2>"$mapFile.linkerr"
    $linkExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($linkExitCode -ne 0) {
    Get-Content "$mapFile.linkerr" -ErrorAction SilentlyContinue | Out-Null
    throw 'Failed to link case firmware. See: ' + $mapFile + '.linkerr'
}

Write-Output "Case $category/$name"
Write-Output "Rust $rustSource"
Write-Output "Out  $firmwareOut"
Write-Output "Map  $mapFile"
