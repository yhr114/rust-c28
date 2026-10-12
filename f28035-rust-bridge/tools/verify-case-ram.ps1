# verify-case-ram.ps1
# JTAG RAM-only case verification: build -> RAM relink -> dss verify, one step.
#
# Why RAM-only: the standard flash-and-verify-case.ps1 loads the .out with
# flash-official.js, which programs FLASHA (the default linker script places
# .text/.cinit in 0x3F6000).  This script instead relinks the same objects
# with RAM-only linker scripts (tools/F28035_ram.cmd + F28035_EABI_sections_ram.cmd)
# so every section lands in SARAM (0x8000-0xA000, M0/M1).  The dss verify-case.js
# then only writes RAM; flash sectors, CSM and boot ROM are untouched.
#
# Usage:
#   .\tools\verify-case-ram.ps1 -Case gpio/gpio_output_basic
#   .\tools\verify-case-ram.ps1 -Case gpio/gpio_output_basic -SkipBuild
#   .\tools\verify-case-ram.ps1 -Case gpio/gpio_output_basic -SkipVerify
#
# PowerShell 5.1 note: with ErrorActionPreference='Stop', stderr from a native
# exe is wrapped as NativeCommandError and terminates the script even when the
# exe exits 0 (e.g. cl2000's harmless "entry-point symbol other than _c_int00"
# warning).  Invoke-Native temporarily lowers EAP to Continue around native
# calls and judges success by $LASTEXITCODE, so a warning can no longer turn a
# successful link into a failing script.

param(
    [string]$Case = '',
    [string]$ExternalCaseRoot = '',
    [string]$VerifierScript = '',

    [string]$Dss = '',
    [string]$TargetConfig = '',
    [string]$Compiler = '',
    [string]$Cargo = '',
    [switch]$SkipBuild,
    [switch]$SkipVerify
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }
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

function Get-FileContentKey {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-FileMetadataKey {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
}

function Get-StringKey {
    param([Parameter(Mandatory = $true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Test-BuildStamp {
    param([string]$Output, [string]$Key)
    $stamp = "$Output.buildstamp"
    return (Test-Path -LiteralPath $Output -PathType Leaf) -and
        (Test-Path -LiteralPath $stamp -PathType Leaf) -and
        ((Get-Content -LiteralPath $stamp -Raw).Trim() -eq $Key)
}

function Set-BuildStamp {
    param([string]$Output, [string]$Key)
    Set-Content -LiteralPath "$Output.buildstamp" -Value $Key -NoNewline
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$dependencyRoot = $projectRoot

if (-not $TargetConfig) {
    $TargetConfig = Join-Path $projectRoot 'targetConfigs\TMS320F28035_XDS100v1.ccxml'
}

if ($ExternalCaseRoot) {
    $caseRoot = (Resolve-Path -LiteralPath $ExternalCaseRoot -ErrorAction Stop).Path
    $category = 'external'
    $name = Split-Path -Leaf $caseRoot
    $caseLabel = "$category/$name"
    $outputDirectory = Join-Path $caseRoot 'build'
} else {
    $parts = $Case.Replace('/', '\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -ne 2) {
        throw 'Specify -Case category/name or -ExternalCaseRoot path'
    }
    $category = $parts[0]
    $name = $parts[1]
    $caseLabel = "$category/$name"
    $caseRoot = Join-Path $projectRoot "app\hardware-tests\$category\$name"
    $outputDirectory = Join-Path $projectRoot "build\$category\$name"
}
$rustSource = Join-Path $caseRoot 'src\main.rs'
$caseManifest = Join-Path $caseRoot 'case.toml'
if (-not (Test-Path -LiteralPath $rustSource -PathType Leaf)) { throw "Rust case entry not found: $rustSource" }
if (-not (Test-Path -LiteralPath $caseManifest -PathType Leaf)) { throw "Case manifest not found: $caseManifest" }

$translatorManifest = Join-Path $dependencyRoot 'tools\rust-to-ti-c\Cargo.toml'
$vendorRoot = Join-Path $dependencyRoot 'platform\vendor\ti\f2803x'
$headers = Join-Path $vendorRoot 'headers\include'
$common = Join-Path $vendorRoot 'common\include'
$commonSource = Join-Path $vendorRoot 'common\source'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$headerLinkerCommand = Join-Path $vendorRoot 'headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
$ramLinkerCommand = Join-Path $PSScriptRoot 'F28035_ram.cmd'
$eabiSectionsRam = Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd'
$peripheralSymbols = Join-Path $dependencyRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'
if ($VerifierScript) {
    $verifyScript = (Resolve-Path -LiteralPath $VerifierScript -ErrorAction Stop).Path
} else {
    $verifyScript = Join-Path $PSScriptRoot 'verify-case.js'
}

foreach ($path in @($Compiler, $Cargo, $translatorManifest, $runtimeLibrary, $ramLinkerCommand, $eabiSectionsRam, $Dss, $TargetConfig, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required input not found: $path" }
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
$ramOut = Join-Path $outputDirectory "$name`_ram.out"
$ramMap = Join-Path $outputDirectory "$name`_ram.map"

if (-not $SkipBuild) {
    Write-Output "== [1/3] Build: translate Rust -> C and compile objects =="

    $previousTarget = $env:CARGO_BUILD_TARGET
    try {
        $env:CARGO_BUILD_TARGET = 'x86_64-pc-windows-msvc'
        $tOut = @(Invoke-Native -FilePath $Cargo -Arguments @('run', '--quiet', "--manifest-path=$translatorManifest", '--', $rustSource, $generatedC))
        if ($LASTEXITCODE -ne 0) {
            $tOut | ForEach-Object { Write-Output $_ }
            throw 'Rust case translation failed.'
        }
    } finally {
        $env:CARGO_BUILD_TARGET = $previousTarget
    }

    $commonOptions = @(
        '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
        '--compile_only', '--gen_func_subsections=on',
        "--include_path=$compilerInclude", "--include_path=$headers", "--include_path=$common",
        "--include_path=$(Join-Path $projectRoot 'sdk\c-abi')"
    )

    # One conservative header key covers all include search paths. Metadata is
    # enough for headers; source and linker inputs below use content hashes.
    $headerFiles = @($compilerInclude, $headers, $common, (Join-Path $projectRoot 'sdk\c-abi')) |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File } |
        Where-Object { $_.Extension -in @('.h', '.hpp', '.inc') } |
        Sort-Object -Property FullName
    $headerKey = ($headerFiles | ForEach-Object { Get-FileMetadataKey $_.FullName }) -join "`n"
    $compilerKey = Get-FileMetadataKey $Compiler

    $steps = @(
        @{ Label = 'generated case C';      IsAsm = $false; In = $generatedC; Out = $caseObject },
        @{ Label = 'C ABI bridge';          IsAsm = $false; In = (Join-Path $projectRoot 'sdk\c-abi\f28035_bridge.c'); Out = $bridgeObject },
        @{ Label = 'firmware entry';        IsAsm = $false; In = (Join-Path $projectRoot 'app\firmware\main.c'); Out = $mainObject },
        @{ Label = 'default interrupts';    IsAsm = $false; In = (Join-Path $projectRoot 'app\firmware\default_interrupts.c'); Out = $defaultInterruptsObject },
        @{ Label = 'system initialization'; IsAsm = $false; In = (Join-Path $commonSource 'DSP2803x_SysCtrl.c'); Out = $sysCtrlObject },
        @{ Label = 'GPIO initialization';   IsAsm = $false; In = (Join-Path $commonSource 'DSP2803x_Gpio.c'); Out = $gpioObject },
        @{ Label = 'delay helper';          IsAsm = $true;  In = (Join-Path $dependencyRoot 'platform\runtime\c28x_us_delay_eabi.asm'); Out = $delayObject },
        @{ Label = 'startup';               IsAsm = $true;  In = (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm'); Out = $startupObject }
    )
    foreach ($s in $steps) {
        $options = if ($s.IsAsm) { $commonOptions } else { $commonOptions + @('--opt_level=2') }
        $keyText = @($compilerKey, $headerKey, ($options -join "`n"),
            (Get-FileContentKey $s.In), $s.In, $s.Out) -join "`n"
        $key = Get-StringKey $keyText
        if (Test-BuildStamp -Output $s.Out -Key $key) {
            Write-Output "Cached: $($s.Label)"
            continue
        }
        Remove-Item -LiteralPath "$($s.Out).buildstamp" -ErrorAction SilentlyContinue
        if ($s.IsAsm) {
            $cOut = @(Invoke-Native -FilePath $Compiler -Arguments ($commonOptions + @("--output_file=$($s.Out)", $s.In)))
        } else {
            $cOut = @(Invoke-Native -FilePath $Compiler -Arguments ($commonOptions + @('--opt_level=2', "--output_file=$($s.Out)", $s.In)))
        }
        if ($LASTEXITCODE -ne 0) {
            $cOut | ForEach-Object { Write-Output $_ }
            throw "Failed to compile $($s.Label)."
        }
        Set-BuildStamp -Output $s.Out -Key $key
    }
    Write-Output "Objects ready: $outputDirectory"
} else {
    Write-Output "== [1/3] Build: skipped (-SkipBuild) =="
}

$objects = @($startupObject, $mainObject, $defaultInterruptsObject, $caseObject, $bridgeObject, $sysCtrlObject, $gpioObject, $delayObject)
foreach ($obj in $objects) {
    if (-not (Test-Path -LiteralPath $obj)) { throw "Object missing (run without -SkipBuild): $obj" }
}

Write-Output "== [2/3] RAM link (all sections -> SARAM, no flash) =="
$linkInputs = @($ramLinkerCommand, $eabiSectionsRam, $peripheralSymbols, $headerLinkerCommand)
$linkArgs = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
    '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
    '--unused_section_elimination=on', '--warn_sections',
    "--map_file=$ramMap", "--output_file=$ramOut") + $objects + $linkInputs + @($runtimeLibrary)
$linkKeyParts = @((Get-FileMetadataKey $Compiler), (Get-FileMetadataKey $runtimeLibrary), ($linkArgs -join "`n"))
foreach ($inputPath in ($objects + $linkInputs)) {
    $linkKeyParts += "$inputPath|$(Get-FileContentKey $inputPath)"
}
$linkKey = Get-StringKey ($linkKeyParts -join "`n")
if ((Test-BuildStamp -Output $ramOut -Key $linkKey) -and (Test-Path -LiteralPath $ramMap -PathType Leaf)) {
    Write-Output "Cached: RAM firmware link"
} else {
    Remove-Item -LiteralPath "$ramOut.buildstamp" -ErrorAction SilentlyContinue
    $lOut = @(Invoke-Native -FilePath $Compiler -Arguments $linkArgs)
    if ($LASTEXITCODE -ne 0) {
        $lOut | ForEach-Object { Write-Output $_ }
        throw 'Failed to link RAM firmware.'
    }
    if (-not (Test-Path -LiteralPath $ramOut) -or -not (Test-Path -LiteralPath $ramMap)) {
        throw "RAM link output missing: $ramOut or $ramMap"
    }
    Set-BuildStamp -Output $ramOut -Key $linkKey
    Write-Output "RAM link OK: $ramOut"
}

if (-not $SkipVerify) {

    # Guard: no code/data section may land in flash range (0x3E0000-0x3F8000).
    $flashRanges = Select-String -Path $ramMap -Pattern '^\s*\.(text|cinit|pinit|econst|const|init_array|switch)\s+' -Encoding UTF8
    foreach ($m in $flashRanges) {
        $cols = @($m.Line -split '\s+' | Where-Object { $_ -ne '' })
        if ($cols.Count -ge 3) {
            $addr = [Convert]::ToInt64($cols[2], 16)
            if ($addr -ge 0x3E0000) {
                throw "Section $($cols[0]) maps to flash-range address 0x$($cols[2]); RAM link is broken."
            }
        }
    }
    Write-Output "== [3/3] JTAG RAM verify (no flash programming) =="
    $vOut = @(Invoke-Native -FilePath $Dss -Arguments @($verifyScript, $TargetConfig, $ramOut))
    $vOut | ForEach-Object { Write-Output $_ }
    if (($vOut -join "`n") -notmatch 'F28035_RUST_CASE=PASS') {
        throw "Target verification failed for $caseLabel"
    }
    Write-Output "RESULT: PASS  $category/$name (RAM verify, flash untouched)"
} else {
    Write-Output "RAM firmware ready: $ramOut"
}
