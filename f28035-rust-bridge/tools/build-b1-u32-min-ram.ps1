#Requires -Version 5.1
# b1-u32-min 最小复现：bundle rustc 编译 → cl2000 汇编启动壳 → TI 链接 RAM。
# 复现 "两个 u16 合成 u32 后与字面量比较" 的代码生成异常。
param([string]$Compiler = '', [string]$Cargo = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'f28035-rust-bridge-b1') 'tools\toolchain-release.ps1')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
$outDir = Join-Path $root 'build\b1-u32-min'
$manifest = Join-Path $root 'crates\b1-u32-min\Cargo.toml'
$startupSource = Join-Path $root 'platform\runtime\u32_probe_ram_start.asm'
$firmware = Join-Path $outDir 'u32_probe_ram.out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$bundle = Get-C28xBundle
$env:RUSTC = $bundle.Rustc
$env:RUSTC_WRAPPER = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\tools\rustc-wrapper.exe'
$env:CARGO_TARGET_DIR = $outDir

& $Toolchain.Cargo rustc --manifest-path $manifest --lib --target c28x-none-elf --release -- --emit=obj,asm
if ($LASTEXITCODE -ne 0) { throw 'cargo rustc (c28x-none-elf) failed.' }
Remove-Item Env:RUSTC, Env:RUSTC_WRAPPER, Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue

$obj = @(Get-ChildItem -LiteralPath $outDir -Recurse -File -Filter 'b1_u32_min-*.o' |
    Sort-Object LastWriteTimeUtc -Descending)[0].FullName
if (-not $obj) { throw 'no object produced' }

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $startObj = Join-Path $outDir 'start.obj'
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$startObj" $startupSource
    if ($LASTEXITCODE -ne 0) { throw 'startup assembly failed.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --rom_model --stack_size=0x100 --unused_section_elimination=on `
        "--output_file=$firmware" `
        $startObj $obj (Join-Path $PSScriptRoot 'F28035_ram.cmd') `
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')
    if ($LASTEXITCODE -ne 0) { throw 'RAM link failed.' }
} finally {
    $ErrorActionPreference = $previousPreference
}

Write-Output "OBJ=$obj"
Write-Output "FIRMWARE=$firmware"
Write-Output 'U32_MIN_BUILD=PASS'
