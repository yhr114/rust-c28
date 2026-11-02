#Requires -Version 5.1
# bare-pac-hwtest RAM 构建：c28x-pac 校准位图的真机下探针（零 C 运行时）。
# 流程与 build-bare-gpio34-ram.ps1 相同：MIR 降级 → cl2000 汇编 → RAM 链接，
# 末尾按 image-stamp 门禁写新鲜度戳（吃自己的狗粮）。
param(
    [string]$Compiler = '',
    [string]$Cargo = '',
    [switch]$SkipBuild,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'build\bare-pac-hwtest'
$source = Join-Path $root 'crates\bare-pac-hwtest\src\lib.rs'
$entry = 'rust_pac_hwtest'
$mir = Join-Path $outDir 'hwtest.mir.txt'
$asm = Join-Path $outDir 'hwtest.asm'
$rustObj = Join-Path $outDir 'hwtest.obj'
$startObj = Join-Path $outDir 'start.obj'
$firmware = Join-Path $outDir 'pac_hwtest_ram.out'
$map = Join-Path $outDir 'pac_hwtest_ram.map'
$startupSource = Join-Path $root 'platform\runtime\pac_hwtest_ram_start.asm'

if ($SkipBuild) {
    Assert-ImageFresh -Image $firmware -Key (New-ImageKey -Label 'bare-pac-hwtest' `
        -Tags @{ entry = $entry; float = 'softlib' } `
        -Files @($source, $startupSource,
            (Join-Path $PSScriptRoot 'F28035_ram.cmd'),
            (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')) `
        -Compiler $Compiler) -Context 'build-bare-pac-hwtest-ram' -AllowStale:$Force
    return
}

foreach ($path in @($Compiler, $source, $startupSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $path" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $source -OutputFile $mir `
    -AssemblyFile $asm -Cargo $Toolchain.MirCargo -RustcArguments '-Zmir-opt-level=4'
if ($LASTEXITCODE -ne 0) { throw 'Rust MIR lowering failed.' }
if (-not (Select-String -Path $mir -Pattern "c28x-codegen: emitted $entry" -Quiet)) {
    throw 'Rust entry was not emitted by the MIR backend.'
}
$asmText = Get-Content -LiteralPath $asm -Raw
if ($asmText -match '(?m)^\s*\.ref\s' -or $asmText -notmatch "${entry}:") {
    throw 'Generated Rust assembly has unresolved external references or no entry.'
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$rustObj" $asm
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble Rust MIR output.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$startObj" $startupSource
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble RAM startup.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --stack_size=0x100 --unused_section_elimination=on `
        "--map_file=$map" "--output_file=$firmware" `
        $startObj $rustObj (Join-Path $PSScriptRoot 'F28035_ram.cmd') `
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')
    if ($LASTEXITCODE -ne 0) { throw 'Zero-C RAM link failed.' }
} finally {
    $ErrorActionPreference = $previousPreference
}
if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) { throw 'Firmware output missing.' }

Set-ImageStamp -Image $firmware -Key (New-ImageKey -Label 'bare-pac-hwtest' `
    -Tags @{ entry = $entry; float = 'softlib' } `
    -Files @($source, $startupSource,
        (Join-Path $PSScriptRoot 'F28035_ram.cmd'),
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')) `
    -Compiler $Compiler)

Write-Output "FIRMWARE=$firmware"
Write-Output 'PAC_HWTEST_BUILD=PASS'
