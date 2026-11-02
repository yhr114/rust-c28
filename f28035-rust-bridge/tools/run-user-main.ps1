#Requires -Version 5.1
param(
    [switch]$Verify,
    [string]$Compiler = '',
    [string]$Cargo = '',
    [string]$Dss = '',
    [string]$TargetConfig = '',
    [string]$BridgeObject = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\user-main-image.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
if (-not $Dss) { $Dss = $Toolchain.Dss }

# TI tools and cargo emit normal progress on stderr; check every exit code.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $TargetConfig) {
    $TargetConfig = Join-Path $root 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}
$outDir = Join-Path $root 'build\user-main'
$mir = Join-Path $outDir 'user_main.mir.txt'
$assembly = Join-Path $outDir 'user_main.asm'
$rustObj = Join-Path $outDir 'user_main.obj'
$harnessObj = Join-Path $outDir 'user_main_test.obj'
$interruptObj = Join-Path $outDir 'default_interrupts.obj'
$sysCtrlObj = Join-Path $outDir 'sysctrl.obj'
$gpioObj = Join-Path $outDir 'gpio.obj'
$delayObj = Join-Path $outDir 'delay.obj'
$startupObj = Join-Path $outDir 'codestart.obj'
$out = Join-Path $outDir 'user_main_ram.out'
$map = Join-Path $outDir 'user_main_ram.map'
$manifest = Join-Path $root 'crates\rust-api\Cargo.toml'
$source = Join-Path $root 'crates\rust-api\src\lib.rs'
$userSource = Join-Path $root 'app\src\main.rs'
$headers = Join-Path $root 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $root 'platform\vendor\ti\f2803x\common\include'
$commonSource = Join-Path $root 'platform\vendor\ti\f2803x\common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtime = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$ofd = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'

foreach ($path in @($Compiler, $Cargo, $manifest, $source, $userSource, $runtime, $ofd)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing build input: $path" }
}
if ($Verify) {
    foreach ($path in @($Dss, $TargetConfig)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JTAG input: $path" }
    }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Push-Location $env:TEMP
try {
    & $Toolchain.HostTestCargo test --manifest-path $manifest --target $Toolchain.HostTestTarget --features one-file-main --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Rust host tests failed.' }
} finally { Pop-Location }

& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile $source -OutputFile $mir -AssemblyFile $assembly -Cargo $Toolchain.MirCargo `
    -OnlyExport rust_user_main `
    -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature=\"one-file-main\"')
if ($LASTEXITCODE -ne 0) { throw 'main.rs is not supported by the C28x MIR backend.' }

if ($BridgeObject) {
    $bridgeObj = (Resolve-Path -LiteralPath $BridgeObject).Path
    if (-not (Test-Path -LiteralPath $bridgeObj -PathType Leaf) -or
        (Get-Item -LiteralPath $bridgeObj).Length -eq 0) {
        throw "Prebuilt C bridge object is missing or empty: $bridgeObj"
    }
    Write-Warning "Using prebuilt C bridge object; the current source is not compiled: $bridgeObj"
} else {
    & (Join-Path $PSScriptRoot 'build-c-bridge.ps1') -Compiler $Compiler -FloatSupport softlib
    if ($LASTEXITCODE -ne 0) { throw 'C bridge build failed.' }
    $bridgeObj = Join-Path $root 'build\c28x\f28035_bridge.obj'
}

$compileOptions = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
    '--compile_only', '--gen_func_subsections=on',
    "--include_path=$compilerInclude", "--include_path=$headers", "--include_path=$common",
    "--include_path=$(Join-Path $root 'sdk\c-abi')"
)
& $Compiler @compileOptions "--output_file=$rustObj" $assembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble Rust MIR output.' }
& $Compiler @compileOptions --opt_level=2 "--output_file=$harnessObj" (Join-Path $root 'platform\firmware\user_main_test.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile user harness.' }
& $Compiler @compileOptions --opt_level=2 "--output_file=$interruptObj" (Join-Path $root 'app\firmware\default_interrupts.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile default Timer0 callback.' }
& $Compiler @compileOptions --opt_level=2 "--output_file=$sysCtrlObj" (Join-Path $commonSource 'DSP2803x_SysCtrl.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile TI system support.' }
& $Compiler @compileOptions --opt_level=2 "--output_file=$gpioObj" (Join-Path $commonSource 'DSP2803x_Gpio.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile TI GPIO support.' }
& $Compiler @compileOptions "--output_file=$delayObj" (Join-Path $root 'platform\runtime\c28x_us_delay_eabi.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble delay helper.' }
& $Compiler @compileOptions "--output_file=$startupObj" (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm')
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble startup.' }

Remove-Item -LiteralPath $out, $map -ErrorAction SilentlyContinue
$linkArgs = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$map", "--output_file=$out",
    $startupObj, $harnessObj, $interruptObj, $rustObj, $bridgeObj, $sysCtrlObj, $gpioObj, $delayObj,
    (Join-Path $root 'tools\F28035_ram.cmd'),
    (Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'),
    (Join-Path $root 'tools\F28035_ramfuncs_zero.cmd'),
    (Join-Path $root 'platform\firmware\F28035_Peripheral_symbols.cmd'),
    (Join-Path $root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
    $runtime
)
& $Compiler @linkArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out -PathType Leaf)) {
    throw 'Failed to link RAM firmware.'
}

$xml = & $ofd -x $out | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Failed to audit firmware segments.' }
$auditedSegments = 0
foreach ($header in [regex]::Matches($xml, '(?s)<elf32_phdr>(.*?)</elf32_phdr>')) {
    $address = [regex]::Match($header.Value, '<p_vaddr>0x([0-9a-fA-F]+)</p_vaddr>')
    $size = [regex]::Match($header.Value, '<p_filesz>0x([0-9a-fA-F]+)</p_filesz>')
    if (-not ($address.Success -and $size.Success)) { continue }
    $start = [Convert]::ToInt64($address.Groups[1].Value, 16)
    $words = [Math]::Ceiling([Convert]::ToInt64($size.Groups[1].Value, 16) / 2.0)
    if ($words -eq 0) { continue }
    $auditedSegments++
    if ($start -ge 0x3e0000) { throw 'RAM build contains a flash loadable segment.' }
    if ($words -gt 0 -and $start -lt 0x3f8000 -and ($start + $words) -gt 0x3f7ff8) {
        throw 'Firmware overlaps the CSM password area.'
    }
}
if ($auditedSegments -eq 0) { throw 'No loadable segment found in the linked firmware.' }
Write-Output "RAM_OUT=$out"
Write-Output 'RAM_ONLY_SEGMENTS=PASS'
Write-Output 'CSM_PASSWORD_AREA=PASS'

# 新鲜度戳：链接+审计成功后记录全部输入指纹（含实际链入的桥 obj 哈希，
# 覆盖 -BridgeObject 预构建旁路）。verify-user-main-flash.ps1 上板前断言。
Set-ImageStamp -Image $out -Key (Get-UserMainImageKey -Compiler $Compiler -ProjectRoot $root -Variant ram)

if ($Verify) {
    $result = @(& $Dss (Join-Path $PSScriptRoot 'verify-user-main.js') $TargetConfig $out 2>&1 | ForEach-Object { "$_" })
    $result | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -notmatch 'USER_MAIN_RAM_JTAG=PASS') {
        throw 'User main RAM/JTAG verification failed.'
    }
}
