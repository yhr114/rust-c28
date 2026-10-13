# build-rustc.ps1 — 增量构建 patched rustc（只编译修改过的文件）
# 用法: .\tools\build-rustc.ps1

$ErrorActionPreference = "Stop"

$rustSrc = "D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad"
$buildDir = "D:\c28x-toolchain\rust-build-gcc14fix"

# 环境变量
$env:PATH = "D:\c28x-toolchain\.lingma\bin;$rustSrc\build\x86_64-pc-windows-gnu\llvm\bin;" + $env:PATH
$env:TEMP = "D:\c28x-toolchain\build-temp"
$env:TMP = "D:\c28x-toolchain\build-temp"

Write-Host "=== 增量构建 rustc（只编译修改过的文件）===" -ForegroundColor Cyan
Write-Host "源码: $rustSrc"
Write-Host "构建: $buildDir"
Write-Host ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Set-Location $rustSrc
python x.py build compiler/rustc --build-dir $buildDir -j 1

$sw.Stop()
Write-Host ""
Write-Host "=== 构建完成，耗时 $($sw.Elapsed.TotalMinutes.ToString('F1')) 分钟 ===" -ForegroundColor Green

# 验证产物
$rustc = "$buildDir\host\stage1\bin\rustc.exe"
if (Test-Path $rustc) {
    $version = & $rustc --version 2>&1
    Write-Host "rustc: $version" -ForegroundColor Green
    Write-Host "路径: $rustc" -ForegroundColor Green
} else {
    Write-Host "ERROR: rustc.exe 未找到" -ForegroundColor Red
    exit 1
}
