param(
    [string]$Compiler = '',
    [ValidateSet('softlib', 'fpu32')]
    [string]$FloatSupport = 'fpu32'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$headers = Join-Path $projectRoot 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\include'
$bridge = Join-Path $projectRoot 'sdk\c-abi\f28035_bridge.c'
$bridgeInclude = Join-Path $projectRoot 'sdk\c-abi'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$outputDirectory = Join-Path $projectRoot 'build\c28x'
$object = Join-Path $outputDirectory 'f28035_bridge.obj'

if (-not (Test-Path -LiteralPath $Compiler)) {
    throw "C28x compiler not found: $Compiler"
}
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf) -or
    (Get-Item -LiteralPath $bridge).Length -eq 0) {
    throw "C ABI bridge source is missing or empty: $bridge"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

& $Compiler `
    --silicon_version=28 `
    --float_support=$FloatSupport `
    --abi=eabi `
    --compile_only `
    --gen_func_subsections=on `
    --include_path=$compilerInclude `
    --include_path=$headers `
    --include_path=$common `
    --include_path=$bridgeInclude `
    --output_file=$object `
    $bridge

if ($LASTEXITCODE -ne 0) {
    throw "cl2000 failed with exit code $LASTEXITCODE"
}

Write-Output "Built $object"
