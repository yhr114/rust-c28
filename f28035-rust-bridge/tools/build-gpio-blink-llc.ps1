# build-gpio-blink.ps1 - 路径2B 快速构建脚本（-O0 -fast-isel 加速）
# 流程: rustc -> .ll(修改DataLayout) -> llc -O0 -fast-isel -> .obj -> cl2000链接 -> .out
# 用法: .\build-gpio-blink-llc.ps1

$ErrorActionPreference = "Stop"

# === 路径配置 ===
$projRoot = "C:\Users\61987\Desktop\28035\f28035-rust-bridge"
$srcDir   = "$projRoot\crates\c28x-gpio-blink\src"
$asmDir   = "$projRoot\crates\c28x-gpio-blink"
$buildDir = "$projRoot\build\c28x-gpio-blink-llc"
$sysroot  = "$projRoot\build\c28x-std"

$rustc = "D:\c28x-toolchain\rustup-gnu\toolchains\nightly-2026-09-14-x86_64-pc-windows-gnu\bin\rustc.exe"
$llc   = "D:\c28x-toolchain\llvm-build-c28x\Release\bin\llc.exe"
$cl2000 = "C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\bin\cl2000.exe"
$asm2000 = "C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\bin\asm2000.exe"

$baseCmd = "$projRoot\tools\F28035_ram.cmd"
$cmdFile = "$projRoot\tools\F28035_EABI_sections_ram.cmd"
$rtsLib  = "C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\lib\rts2800_ml_eabi.lib"

# c28x 的 DataLayout（从 target spec 提取）
$c28xDataLayout = 'e-m:e-p:32:32-i1:8:8-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16'

# === 创建构建目录 ===
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
Set-Location $buildDir

Write-Host "=== Step 1: rustc -> LLVM IR (host target) ===" -ForegroundColor Cyan
& $rustc --emit=llvm-ir --crate-type=lib -C opt-level=0 "$srcDir\main_llc.rs" -o "$buildDir\main_raw.ll" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "rustc FAILED" -ForegroundColor Red; exit 1 }
Write-Host "  main_raw.ll OK" -ForegroundColor Green

Write-Host "=== Step 2: 修改 DataLayout 为 c28x ===" -ForegroundColor Cyan
$content = Get-Content "$buildDir\main_raw.ll" -Raw
# 替换 DataLayout
$content = $content -replace 'target datalayout = ".*?"', "target datalayout = `"$c28xDataLayout`""
# 替换 triple
$content = $content -replace 'target triple = ".*?"', 'target triple = "c28x-none-elf"'
# 无 BOM 写入
[IO.File]::WriteAllText("$buildDir\main.ll", $content, [Text.UTF8Encoding]::new($false))
Write-Host "  main.ll OK (DataLayout 已改为 c28x)" -ForegroundColor Green

Write-Host "=== Step 3: llc -> C28x .obj (O0 + fast-isel) ===" -ForegroundColor Cyan
& $llc -mtriple=c28x-none-elf -O0 -fast-isel -filetype=obj "$buildDir\main.ll" -o "$buildDir\main.obj" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "llc FAILED" -ForegroundColor Red; exit 1 }
Write-Host "  main.obj OK ($([math]::Round((Get-Item "$buildDir\main.obj").Length/1KB,1))KB)" -ForegroundColor Green

Write-Host "=== Step 4: 汇编启动代码和向量表 ===" -ForegroundColor Cyan
& $cl2000 -c "$asmDir\cargo_blink_start.asm" 2>&1 | Out-Null
& $cl2000 -c "$asmDir\c28x_interrupts_no_trampoline.asm" 2>&1 | Out-Null
Move-Item "$asmDir\cargo_blink_start.obj" "$buildDir\" -Force -ErrorAction SilentlyContinue
Move-Item "$asmDir\c28x_interrupts_no_trampoline.obj" "$buildDir\" -Force -ErrorAction SilentlyContinue
Write-Host "  start.obj + vectors.obj OK" -ForegroundColor Green

Write-Host "=== Step 5: cl2000 链接 -> .out ===" -ForegroundColor Cyan
# 从之前的 rlib 中提取 c28x_pac 的 .obj
$pacRlib = "$sysroot\libc28x_pac.rlib"
if (Test-Path $pacRlib) {
    Write-Host "  提取 c28x_pac.obj..."
    # rlib 就是 ar 归档，用 llvm-ar 提取
    $llvmAr = "D:\c28x-toolchain\llvm-build-c28x\Release\bin\llvm-ar.exe"
    if (Test-Path $llvmAr) {
        Push-Location $buildDir
        & $llvmAr x $pacRlib 2>&1 | Out-Null
        Pop-Location
    }
}

& $cl2000 --run_linker `
    "$buildDir\main.obj" `
    "$buildDir\cargo_blink_start.obj" `
    "$buildDir\c28x_interrupts_no_trampoline.obj" `
    $rtsLib $baseCmd $cmdFile `
    -o "$buildDir\gpio_blink.out" `
    -m "$buildDir\gpio_blink.map" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "link FAILED" -ForegroundColor Red; exit 1 }
Write-Host "  gpio_blink.out OK ($([math]::Round((Get-Item "$buildDir\gpio_blink.out").Length/1KB,1))KB)" -ForegroundColor Green

Write-Host ""
Write-Host "=== 构建完成! ===" -ForegroundColor Green
Write-Host "输出: $buildDir\gpio_blink.out"
Write-Host "优化级别: -O0 -fast-isel（调试快速编译模式）"
