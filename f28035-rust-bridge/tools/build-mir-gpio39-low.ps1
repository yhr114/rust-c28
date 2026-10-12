param(
    [string]$Compiler = '',
    [string]$Cargo = '',
    [ValidateSet('softlib')]
    [string]$FloatSupport = 'softlib'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

# Continue throughout: every failure below is an explicit
# `if ($LASTEXITCODE -ne 0) { throw }` check, and cl2000/cargo write normal
# progress to stderr which PS5.1 would otherwise promote to terminating
# NativeCommandError records under 'Stop'.
$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\mir-gpio39-low'
$mirDirectory = Join-Path $projectRoot 'build\mir'
$rustSource = Join-Path $projectRoot 'crates\rust-api\src\lib.rs'
$rustManifest = Join-Path $projectRoot 'crates\rust-api\Cargo.toml'
$mirOutput = Join-Path $mirDirectory 'gpio39-safe.mir.txt'
$assembly = Join-Path $mirDirectory 'gpio39-safe.asm'
$rustObject = Join-Path $outputDirectory 'rust_gpio39_low.obj'
$harnessObject = Join-Path $outputDirectory 'gpio39_low_test.obj'
$bridgeObject = Join-Path $projectRoot 'build\c28x\f28035_bridge.obj'
$sysCtrlObject = Join-Path $outputDirectory 'sysctrl.obj'
$gpioObject = Join-Path $outputDirectory 'gpio.obj'
$delayObject = Join-Path $outputDirectory 'delay.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$firmwareOut = Join-Path $outputDirectory 'gpio39_low_mir.out'
$firmwareHex = Join-Path $outputDirectory 'gpio39_low_mir.hex'
$mapFile = Join-Path $outputDirectory 'gpio39_low_mir.map'
$headers = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\include'
$commonSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$objectDisplay = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'
$linkerCommand = Join-Path $projectRoot 'tools\F28035_ram.cmd'
$headerLinkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$eabiSections = Join-Path $projectRoot 'tools\F28035_EABI_sections_ram.cmd'
$peripheralSymbols = Join-Path $projectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'
$harnessSource = Join-Path $projectRoot 'platform\firmware\gpio39_low_test.c'

foreach ($required in @($Compiler, $Cargo, $hexConverter, $objectDisplay, $rustSource, $runtimeLibrary)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required build input not found: $required"
    }
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

# Run host tests outside the repository so the C28x .cargo build-std settings
# do not affect the x86_64 test build.  PS5.1 promotes cargo's normal stderr
# progress lines to NativeCommandError records, so capture with Continue and
# judge by $LASTEXITCODE.
Push-Location $env:TEMP
try {
    $testOut = @(& $Cargo test --manifest-path $rustManifest --target x86_64-pc-windows-msvc 2>&1 | ForEach-Object { "$_" })
    $testExit = $LASTEXITCODE
    if ($testExit -ne 0) {
        $testOut | Select-Object -Last 8 | ForEach-Object { Write-Output $_ }
        throw 'Safe HAL host tests failed.'
    }
} finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot 'build-c-bridge.ps1') -Compiler $Compiler -FloatSupport $FloatSupport
if ($LASTEXITCODE -ne 0) { throw 'C bridge build failed.' }

# c28x-mir invokes rustc_driver, so this application is type checked and
# borrow checked by rustc before the optimized MIR is lowered to C28x asm.
& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile $rustSource -OutputFile $mirOutput -AssemblyFile $assembly -Cargo $Cargo `
    -RustcArguments '-Zmir-opt-level=4'
if ($LASTEXITCODE -ne 0) { throw 'Safe GPIO39 MIR lowering failed.' }

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
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble rustc-MIR GPIO39 output.' }
& $Compiler @commonOptions --opt_level=2 --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO39 verification harness.' }
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
    $startupObject $harnessObject $rustObject $bridgeObject $sysCtrlObject $gpioObject `
    $delayObject $linkerCommand $eabiSections $peripheralSymbols `
    $headerLinkerCommand $runtimeLibrary
if ($LASTEXITCODE -ne 0) { throw 'Failed to link rustc-MIR GPIO39 firmware.' }

# A loadable segment at the F28035 password locations can make the device
# unrecoverable after reset. Audit the linked image, not only the map file.
$objectXml = & $objectDisplay -x $firmwareOut | Out-String
if ($LASTEXITCODE -ne 0) { throw 'ofd2000 failed while auditing CSM password addresses.' }
$passwordStart = 0x3f7ff8L
$passwordEndExclusive = 0x3f8000L
foreach ($header in [regex]::Matches($objectXml, '(?s)<elf32_phdr>(.*?)</elf32_phdr>')) {
    $addressMatch = [regex]::Match($header.Value, '<p_vaddr>0x([0-9a-fA-F]+)</p_vaddr>')
    $sizeMatch = [regex]::Match($header.Value, '<p_filesz>0x([0-9a-fA-F]+)</p_filesz>')
    if (-not ($addressMatch.Success -and $sizeMatch.Success)) { continue }

    $segmentStart = [Convert]::ToInt64($addressMatch.Groups[1].Value, 16)
    $fileBytes = [Convert]::ToInt64($sizeMatch.Groups[1].Value, 16)
    $segmentWords = [Math]::Ceiling($fileBytes / 2.0)
    $segmentEndExclusive = $segmentStart + $segmentWords
    if ($fileBytes -gt 0 -and $segmentStart -lt $passwordEndExclusive -and
        $segmentEndExclusive -gt $passwordStart) {
        throw ('Unsafe firmware: loadable segment 0x{0:x}-0x{1:x} overlaps the CSM password area.' -f `
            $segmentStart, ($segmentEndExclusive - 1))
    }
}
Write-Output 'CSM password-area audit: PASS (no loadable segment overlaps 0x3F7FF8..0x3F7FFF)'

& $hexConverter --intel --byte --memwidth=16 --romwidth=16 --outfile=$firmwareHex $firmwareOut
if ($LASTEXITCODE -ne 0) { throw 'hex2000 failed.' }

Write-Output "Rust $rustSource"
Write-Output "MIR  $mirOutput"
Write-Output "Asm  $assembly"
Write-Output "Out  $firmwareOut"
Write-Output "Hex  $firmwareHex"
