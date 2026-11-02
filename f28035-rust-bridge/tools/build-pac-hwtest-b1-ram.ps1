#Requires -Version 5.1
# pac-hwtest-b1 RAM 构建：真身 c28x-pac crate 的 B-1 真机探针。
# 路径：active B-1 bundle rustc（c28x-none-elf）编译 Rust bin → cl2000 汇编
# 启动壳 → TI 链接 RAM 映像 → image-stamp 写新鲜度戳。
# 真机校验用 tools/verify-pac-hwtest-b1-ram.ps1（dss 读邮箱）。
param(
    [string]$Compiler = '',
    [string]$Cargo = '',
    [switch]$SkipBuild,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'f28035-rust-bridge-b1') 'tools\toolchain-release.ps1')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'build\pac-hwtest-b1'
$manifest = Join-Path $root 'crates\pac-hwtest-b1\Cargo.toml'
$startupSource = Join-Path $root 'platform\runtime\pac_hwtest_ram_start.asm'
$eallowSource = Join-Path $root 'platform\runtime\pac_hwtest_eallow.asm'
$firmware = Join-Path $outDir 'pac_hwtest_ram.out'

$stampKey = {
    New-ImageKey -Label 'pac-hwtest-b1' `
        -Tags @{ entry = 'rust_pac_hwtest'; float = 'softlib' } `
        -Files @((Join-Path $root 'crates\pac-hwtest-b1\src\main.rs'),
            (Join-Path $root 'crates\pac-hwtest-b1\Cargo.toml'),
            (Join-Path $root 'crates\c28x-pac\src\lib.rs'),
            (Join-Path $root 'crates\c28x-pac\Cargo.toml'),
            $startupSource,
            (Join-Path $PSScriptRoot 'F28035_ram.cmd'),
            (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')) `
        -Compiler $BundleRustc
}

if (-not $Compiler) { $Compiler = $Toolchain.Compiler }

if ($SkipBuild) {
    $BundleRustc = (Get-C28xBundle).Rustc
    Assert-ImageFresh -Image $firmware -Key (& $stampKey) `
        -Context 'build-pac-hwtest-b1-ram' -AllowStale:$Force
    return
}

if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
$BundleRustc = (Get-C28xBundle).Rustc
if (-not (Test-Path -LiteralPath $BundleRustc)) { throw "B-1 bundle rustc not found: $BundleRustc" }
foreach ($path in @($Compiler, $Cargo, $manifest, $startupSource)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$env:RUSTC = $BundleRustc
$env:RUSTC_WRAPPER = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\tools\rustc-wrapper.exe'
$env:CARGO_TARGET_DIR = $outDir

# 两个 --lib --emit=obj（lib 不触发链接，b1 verify 同款）：
#   1) c28x-pac 真身对象（含 PERIPHERALS_TAKEN 等 .bss 符号）
#   2) 探针对象（PAC 方法全部 #[inline(always)]，内联进探针代码）
# bin 形态会被 GNU ld 拒绝（"Relocations in generic ELF"），故不用 bin。
& $Cargo rustc --manifest-path (Join-Path $root 'crates\c28x-pac\Cargo.toml') `
    --lib --target c28x-none-elf --release -- --emit=obj
if ($LASTEXITCODE -ne 0) { throw 'cargo rustc c28x-pac failed.' }
& $Cargo rustc --manifest-path $manifest --lib --target c28x-none-elf --release -- --emit=obj
if ($LASTEXITCODE -ne 0) { throw 'cargo rustc (c28x-none-elf) failed.' }
Remove-Item Env:RUSTC, Env:RUSTC_WRAPPER, Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue

$rustObjects = @(Get-ChildItem -LiteralPath $outDir -Recurse -File -Filter '*.o' |
    Where-Object Name -match '^(pac_hwtest_b1|c28x_pac)-' |
    Sort-Object LastWriteTimeUtc -Descending)
if ($rustObjects.Count -lt 2) { throw "cargo did not produce both C28x objects (got $($rustObjects.Count))" }
$rustObj = $rustObjects[0].FullName
$pacObj = ($rustObjects | Where-Object Name -match '^c28x_pac-')[0].FullName

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $startObj = Join-Path $outDir 'start.obj'
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$startObj" $startupSource
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble RAM startup.' }
    $eallowObj = Join-Path $outDir 'eallow.obj'
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --compile_only `
        "--output_file=$eallowObj" $eallowSource
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble EALLOW leaf functions.' }
    & $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
        --entry_point=code_start --rom_model --stack_size=0x100 --unused_section_elimination=on `
        "--output_file=$firmware" `
        $startObj $eallowObj $rustObj $pacObj (Join-Path $PSScriptRoot 'F28035_ram.cmd') `
        (Join-Path $PSScriptRoot 'F28035_EABI_sections_ram.cmd')
    if ($LASTEXITCODE -ne 0) { throw 'RAM link failed.' }
} finally {
    $ErrorActionPreference = $previousPreference
}
if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) { throw 'Firmware output missing.' }

Set-ImageStamp -Image $firmware -Key (& $stampKey)

Write-Output "FIRMWARE=$firmware"
Write-Output 'PAC_HWTEST_B1_BUILD=PASS'
