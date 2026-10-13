# F28035 Rust 一键构建脚本
# 用法: .\build.ps1 [clean]
#   clean - 清理构建产物后重新构建

param([switch]$Clean)

$ErrorActionPreference = "Stop"
$proj = "C:\Users\61987\Desktop\28035\f28035-rust-bridge"
$blink = "$proj\crates\c28x-gpio-blink"
$build = "$proj\build\c28x-gpio-blink"
$pacExtract = "$proj\build\c28x-pac-extract"
$stdObjs = "$proj\build\c28x-std\objs"
$tools = "$proj\tools"

# 工具链路径
$rustc = "D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe"
$llvmAr = "D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin\llvm-ar.exe"
$tiBin = "C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\bin"
$rtsLib = "C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\lib\rts2800_ml_eabi.lib"
$mingwBin = "E:\Qt\Tools\mingw810_64\bin"

# 环境
$env:PATH = "$mingwBin;$tiBin;$env:PATH"
$env:RUSTC = $rustc
$env:RUSTDOC = $rustc

if ($Clean) {
    Write-Host "[clean] 清理构建产物..."
    Remove-Item "$build\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$pacExtract\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$blink\target" -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $build -Force | Out-Null
New-Item -ItemType Directory -Path $pacExtract -Force | Out-Null

# Step 1: cargo rustc 编译
Write-Host "[1/4] cargo rustc 编译..."
Push-Location $blink
cargo rustc --release --target c28x-none-elf -- --emit=obj 2>&1 | ForEach-Object { Write-Host $_ }
$rustObj = Get-ChildItem "$blink\target\c28x-none-elf\release\build\c28x-gpio-blink\*\out\*.o" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $rustObj) { Pop-Location; throw "cargo rustc 失败：未找到输出 .o 文件" }
Copy-Item $rustObj.FullName "$build\gpio-blink.o" -Force
Pop-Location
Write-Host "      -> gpio-blink.o ($((Get-Item "$build\gpio-blink.o").Length) bytes)"

# Step 2: 提取 PAC .o
Write-Host "[2/4] 提取 PAC 目标文件..."
$pacRlib = Get-ChildItem "$blink\target\c28x-none-elf\release\build\c28x-pac\*\out\libc28x_pac-*.rlib" | Select-Object -First 1
if (-not $pacRlib) { throw "找不到 PAC rlib" }
Push-Location $pacExtract
& $llvmAr x $pacRlib.FullName 2>&1 | Out-Null
Pop-Location
$pacObj = Get-ChildItem "$pacExtract\*.o" | Select-Object -First 1
Write-Host "      -> $($pacObj.Name) ($($pacObj.Length) bytes)"

# Step 3: 汇编启动代码和中断向量表
Write-Host "[3/4] 汇编启动代码和中断向量表..."
& cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$build\cargo_blink_start.obj" "$blink\cargo_blink_start.asm" 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "汇编 cargo_blink_start.asm 失败" }
& cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$build\c28x_interrupts.obj" "$blink\c28x_interrupts.asm" 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "汇编 c28x_interrupts.asm 失败" }
Write-Host "      -> cargo_blink_start.obj, c28x_interrupts.obj"

# Step 4: 链接
Write-Host "[4/4] 链接..."
$out = "$build\gpio_blink.out"
$map = "$build\gpio_blink.map"
Remove-Item $out, $map -ErrorAction SilentlyContinue
& cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --run_linker --rom_model --stack_size=0x100 --unused_section_elimination=on --entry_point=code_start "--map_file=$map" "--output_file=$out" "$build\gpio-blink.o" "$build\cargo_blink_start.obj" "$build\c28x_interrupts.obj" $pacObj.FullName "$stdObjs\core-cgu.0.rcgu.o" "$stdObjs\builtins-cgu.0.rcgu.o" "$tools\F28035_ram.cmd" "$tools\F28035_EABI_sections_ram.cmd" 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "链接失败" }

$size = (Get-Item $out).Length
Write-Host ""
Write-Host "=== 构建成功 ===" -ForegroundColor Green
Write-Host "输出: $out"
Write-Host "大小: $size bytes"
