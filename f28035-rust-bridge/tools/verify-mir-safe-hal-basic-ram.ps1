#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Harness,

    [Parameter(Mandatory = $true)]
    [string]$VerifyJs,

    [Parameter(Mandatory = $true)]
    [string]$PassToken,

    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml',
    [string]$Xds100Serial = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }
if (-not $Xds100Serial) { $Xds100Serial = $Toolchain.Xds100Serial }

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$baseOutDir = Join-Path $root 'build\mir-control-loop'
$outDir = Join-Path $root "build\mir-$Name-ram"
$harnessSource = Join-Path $root "platform\firmware\$Harness"
$verifyScript = Join-Path $PSScriptRoot $VerifyJs
$harnessObject = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($Harness) + '.obj')
$ramOut = Join-Path $outDir "$Name`_ram.out"
$ramMap = Join-Path $outDir "$Name`_ram.map"

foreach ($p in @($Compiler, $Dss, $TargetConfig, $harnessSource, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if (-not $SkipBuild) {
    Write-Output '== [1/4] Build shared Safe HAL MIR objects =='
    & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1') -Compiler $Compiler
    if ($LASTEXITCODE -ne 0) { throw 'Safe HAL MIR object build failed.' }
}

Write-Output '== [2/4] Compile one-case C harness =='
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$headers = Join-Path $root 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $root 'platform\vendor\ti\f2803x\common\include'
$commonOptions = @(
    '--silicon_version=28',
    '--float_support=softlib',
    '--abi=eabi',
    '--compile_only',
    '--gen_func_subsections=on',
    "--include_path=$compilerInclude",
    "--include_path=$headers",
    "--include_path=$common"
)
& $Compiler @commonOptions --opt_level=2 --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) { throw "Failed to compile harness: $Harness" }

Write-Output '== [3/4] RAM relink one-case firmware =='
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$objects = @(
    (Join-Path $baseOutDir 'codestart.obj'),
    $harnessObject,
    (Join-Path $baseOutDir 'rust_control_loop.obj'),
    (Join-Path $root 'build\c28x\f28035_bridge.obj'),
    (Join-Path $baseOutDir 'sysctrl.obj'),
    (Join-Path $baseOutDir 'gpio.obj'),
    (Join-Path $baseOutDir 'delay.obj')
)
foreach ($o in $objects) { if (-not (Test-Path -LiteralPath $o)) { throw "Missing object: $o" } }

Remove-Item $ramOut, $ramMap -ErrorAction SilentlyContinue
$linkArgs = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$ramMap", "--output_file=$ramOut"
) + $objects + @(
    (Join-Path $root 'tools\F28035_ram.cmd'),
    (Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'),
    (Join-Path $PSScriptRoot 'F28035_ramfuncs_zero.cmd'),
    (Join-Path $root 'platform\firmware\F28035_Peripheral_symbols.cmd'),
    (Join-Path $root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
    $runtimeLibrary
)
$linkOut = @(& $Compiler @linkArgs 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ramOut)) {
    $linkOut | ForEach-Object { Write-Output $_ }
    throw 'RAM relink failed.'
}

$flashHits = Select-String -Path $ramMap -Pattern '^\s*\.(text|cinit|econst|const)\s+' | ForEach-Object {
    $c = @($_.Line -split '\s+' | Where-Object { $_ -ne '' })
    if ($c.Count -ge 3 -and [Convert]::ToInt64($c[2], 16) -ge 0x3E0000) { $_.Line }
}
if ($flashHits) { throw "RAM link leaked into flash: $($flashHits -join ' | ')" }
Write-Output "RAM link OK: $ramOut"

Write-Output '== [4/4] JTAG RAM verify one-case firmware =='
if (Test-Path -LiteralPath $Xds100Serial) {
    $probe = @(& $Xds100Serial 2>&1 | ForEach-Object { "$_" })
    if (($probe -join "`n") -match 'No XDS100 emulators were found') {
        $probe | ForEach-Object { Write-Output $_ }
        throw 'No XDS100 emulator is currently enumerated; RAM/JTAG verification cannot run.'
    }
}
$vOut = @(& $Dss $verifyScript $TargetConfig $ramOut 2>&1 | ForEach-Object { "$_" })
$vOut | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) {
    throw "dss exited $LASTEXITCODE while verifying $Name."
}
if (($vOut -join "`n") -notmatch [regex]::Escape($PassToken)) {
    throw "Target verification failed for $Name."
}
Write-Output "RESULT: PASS  $Name (Safe HAL MIR true-compile, RAM verify, flash untouched)"
