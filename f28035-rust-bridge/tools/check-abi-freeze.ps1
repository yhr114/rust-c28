# ABI 冻结一致性检查（零依赖，本机可运行）
# 用法:  powershell -ExecutionPolicy Bypass -File tools\check-abi-freeze.ps1
# 退出码: 0 = 通过, 1 = 违反冻结规范
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent $root
$b1Root = Join-Path $workspace 'f28035-rust-bridge-b1'

$canonicalLayout = 'e-m:e-p:32:32-i1:8:8-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16'
$forbidden = @('p:16:16-i', 'pointer_width: 16,', '"target-pointer-width": 16')

$requiredFiles = @(
    (Join-Path $root 'backend\llvm-c28x\C28xTargetMachine.cpp'),
    (Join-Path $root 'crates\c28x-rt\c28x-none-elf.json'),
    (Join-Path $b1Root 'backend\llvm-c28x\rustc-patches\c28x_none_elf_1_100.rs')
)

$scanDirs = @(
    (Join-Path $root 'backend\llvm-c28x'),
    (Join-Path $root 'crates\c28x-rt'),
    (Join-Path $b1Root 'backend\llvm-c28x\rustc-patches')
)

$excludeDirNames = @('build', 'vendor', 'target', '.git', 'node_modules')

function Get-ScanFiles {
    $files = @()
    foreach ($dir in $scanDirs) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Recurse -File | ForEach-Object {
            $skip = $false
            foreach ($ex in $excludeDirNames) {
                if ($_.FullName -match "\\$ex\\") { $skip = $true; break }
            }
            if (-not $skip) { $files += $_.FullName }
        }
    }
    return ,$files
}

$failures = @()

foreach ($file in (Get-ScanFiles)) {
    $text = Get-Content -Raw -LiteralPath $file -ErrorAction SilentlyContinue
    if ($null -eq $text) { continue }
    foreach ($tok in $forbidden) {
        if ($text.Contains($tok)) {
            $failures += "FORBIDDEN token '$tok' in $file"
        }
    }
}

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $failures += "MISSING required file: $file"
        continue
    }
    $text = Get-Content -Raw -LiteralPath $file
    if (-not $text.Contains($canonicalLayout)) {
        $failures += "MISSING canonical data-layout in $file"
    }
}

foreach ($jsonRelative in @('crates\c28x-rt\c28x-none-elf.json')) {
    $jsonFile = Join-Path $root $jsonRelative
    if (-not (Test-Path $jsonFile)) { continue }
    $json = Get-Content -Raw -LiteralPath $jsonFile | ConvertFrom-Json
    if ($json.'target-pointer-width' -ne 32) {
        $failures += "$jsonRelative target-pointer-width must be 32 (got $($json.'target-pointer-width'))"
    }
    if ($json.'data-layout' -ne $canonicalLayout) {
        $failures += "$jsonRelative data-layout must be canonical"
    }
    if ($json.'arch' -ne 'c28x' -or $json.'llvm-target' -ne 'c28x-ti-none') {
        $failures += "$jsonRelative must select the C28x architecture and LLVM target"
    }
}

if ($failures.Count -gt 0) {
    Write-Host "ABI FREEZE CHECK: FAIL" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "ABI FREEZE CHECK: PASS" -ForegroundColor Green
Write-Host "  canonical layout: $canonicalLayout"
Write-Host "  scanned files   : $((Get-ScanFiles).Count)"
exit 0
