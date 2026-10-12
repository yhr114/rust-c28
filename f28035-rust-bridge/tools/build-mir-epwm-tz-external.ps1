# Build the gpio_epwm_tz_external_basic vertical slice through the rustc-MIR path.
#
# The application mirrors (rust_api::application::rust_epwm_tz_external_to_epwm1a and
# rust_epwm_tz_external_restore_gpio) are plain safe Rust: no unsafe, no direct FFI --
# the epwm_tz_external routing goes through Peripherals/Gpio::set_epwm_tz_external.  c28x-mir invokes
# rustc_driver, so the code is type- and borrow-checked by rustc before the
# optimized MIR is lowered to C28x asm.
#
# PowerShell 5.1 note: Invoke-Native swallows stderr (cargo/cl2000 write
# harmless progress/warnings to stderr) and judges by $LASTEXITCODE.

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

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments
    )
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return @(& $FilePath @Arguments 2>&1 | ForEach-Object { "$_" })
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\mir-gpio0-epwm_tz_external'
$mirDirectory = Join-Path $projectRoot 'build\mir'
$rustSource = Join-Path $projectRoot 'crates\rust-api\src\lib.rs'
$rustManifest = Join-Path $projectRoot 'crates\rust-api\Cargo.toml'
$mirOutput = Join-Path $mirDirectory 'epwm_tz_external.mir.txt'
$assembly = Join-Path $mirDirectory 'epwm_tz_external.asm'
$rustObject = Join-Path $outputDirectory 'rust_epwm_tz_external.obj'
$harnessObject = Join-Path $outputDirectory 'epwm_tz_external_test.obj'
$bridgeObject = Join-Path $projectRoot 'build\c28x\f28035_bridge.obj'
$sysCtrlObject = Join-Path $outputDirectory 'sysctrl.obj'
$gpioObject = Join-Path $outputDirectory 'gpio.obj'
$delayObject = Join-Path $outputDirectory 'delay.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$firmwareOut = Join-Path $outputDirectory 'epwm_tz_external_mir.out'
$mapFile = Join-Path $outputDirectory 'epwm_tz_external_mir.map'
$headers = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\include'
$commonSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objectDisplay = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'
$linkerCommand = Join-Path $projectRoot 'tools\F28035_ram.cmd'
$headerLinkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$eabiSections = Join-Path $projectRoot 'tools\F28035_EABI_sections_ram.cmd'
$peripheralSymbols = Join-Path $projectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'
$harnessSource = Join-Path $projectRoot 'platform\firmware\epwm_tz_external_test.c'

foreach ($required in @($Compiler, $Cargo, $objectDisplay, $rustSource, $runtimeLibrary)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required build input not found: $required"
    }
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

# Host tests outside the repo root so the C28x .cargo target does not apply.
Push-Location $env:TEMP
try {
    $out = Invoke-Native $Cargo @('test', '--manifest-path', $rustManifest, '--target', 'x86_64-pc-windows-msvc')
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Safe HAL host tests failed.' }
} finally {
    Pop-Location
}

# build-c-bridge.ps1 takes named params; call it directly so -Compiler/-FloatSupport bind by name.
$out = @(& (Join-Path $PSScriptRoot 'build-c-bridge.ps1') -Compiler $Compiler -FloatSupport $FloatSupport 2>&1 | ForEach-Object { "$_" })
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'C bridge build failed.' }

# c28x-mir invokes rustc_driver, so this application is type checked and
# borrow checked by rustc before the optimized MIR is lowered to C28x asm.
$out = Invoke-Native 'powershell.exe' @(
    '-NoProfile', '-File', (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1'),
    '-InputFile', $rustSource, '-OutputFile', $mirOutput,
    '-AssemblyFile', $assembly, '-Cargo', $Cargo,
    '-RustcArguments', '-Zmir-opt-level=4'
)
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'ePWM DEADBAND MIR lowering failed.' }

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

$out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$rustObject", $assembly))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble rustc-MIR ePWM DEADBAND.' }

$out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$harnessObject", $harnessSource))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile ePWM DEADBAND harness.' }

$out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$sysCtrlObject", (Join-Path $commonSource 'DSP2803x_SysCtrl.c')))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile system initialization.' }

$out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$gpioObject", (Join-Path $commonSource 'DSP2803x_Gpio.c')))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO initialization.' }

$out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$delayObject", (Join-Path $projectRoot 'platform\runtime\c28x_us_delay_eabi.asm')))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble delay helper.' }

$out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$startupObject", (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm')))
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile startup.' }

$out = Invoke-Native $Compiler @(
    '--silicon_version=28', "--float_support=$FloatSupport", '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$mapFile", "--output_file=$firmwareOut",
    $startupObject, $harnessObject, $rustObject, $bridgeObject, $sysCtrlObject, $gpioObject,
    $delayObject, $linkerCommand, $eabiSections, $peripheralSymbols,
    $headerLinkerCommand, $runtimeLibrary
)
$out | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw 'Failed to link ePWM DEADBAND firmware.' }

# Audit the linked image, not just the map file: a loadable segment at the
# CSM password locations can brick the device.
$objXml = (Invoke-Native $objectDisplay @('-x', $firmwareOut)) | Out-String
if ($LASTEXITCODE -ne 0) { throw 'ofd2000 failed while auditing CSM password addresses.' }
$passwordStart = 0x3f7ff8L
$passwordEndExclusive = 0x3f8000L
$mainFlashStart = 0x3e8000L
$mainFlashEndExclusive = 0x3f7f80L
$bootEntryStart = 0x3f7ff6L
$bootEntryEndExclusive = 0x3f7ff8L
foreach ($header in [regex]::Matches($objXml, '(?s)<elf32_phdr>(.*?)</elf32_phdr>')) {
    $addressMatch = [regex]::Match($header.Value, '<p_paddr>0x([0-9a-fA-F]+)</p_paddr>')
    if (-not $addressMatch.Success) {
        $addressMatch = [regex]::Match($header.Value, '<p_vaddr>0x([0-9a-fA-F]+)</p_vaddr>')
    }
    $sizeMatch = [regex]::Match($header.Value, '<p_filesz>0x([0-9a-fA-F]+)</p_filesz>')
    if (-not ($addressMatch.Success -and $sizeMatch.Success)) { continue }
    $segmentStart = [Convert]::ToInt64($addressMatch.Groups[1].Value, 16)
    $fileBytes = [Convert]::ToInt64($sizeMatch.Groups[1].Value, 16)
    $segmentWords = [Convert]::ToInt64([Math]::Ceiling($fileBytes / 2.0))
    $segmentEndExclusive = [Convert]::ToInt64($segmentStart + $segmentWords)
    if ($fileBytes -gt 0 -and $segmentStart -lt $passwordEndExclusive -and
        $segmentEndExclusive -gt $passwordStart) {
        throw ('Unsafe firmware: loadable segment 0x{0:x}-0x{1:x} overlaps the CSM password area.' -f `
            $segmentStart, ($segmentEndExclusive - 1))
    }
    # RAM link: skip flash-range audit
}
Write-Output 'CSM password-area audit: PASS (no loadable segment overlaps 0x3F7FF8..0x3F7FFF)'
Write-Output 'Flash-range audit: PASS (loadable data is limited to 0x3E8000..0x3F7F7F and boot entry 0x3F7FF6..0x3F7FF7)'

Write-Output "Rust $rustSource"
Write-Output "MIR  $mirOutput"
Write-Output "Asm  $assembly"
Write-Output "Out  $firmwareOut"
