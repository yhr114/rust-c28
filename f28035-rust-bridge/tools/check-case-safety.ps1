#Requires -Version 5.1
# check-case-safety.ps1
# 应用层 unsafe/FFI 门禁扫描：对 app/hardware-tests 下每个 case 的 src/main.rs
# 分类其安全调用方式，输出统计与清单。
#
# 分类：
#   SAFE-HAL    只 use f28035_safe_hal，无 extern "C"/unsafe/裸指针（P1 目标态）
#   mixed       use f28035_safe_hal，但仍有 extern "C" 或 unsafe（部分迁移）
#   direct-FFI  未用 safe-hal，直接 extern "C" 调 f28035_*（待迁移）
#   scaffold    既无 safe-hal 也无 FFI（骨架/空 main）
#
# 另读取每个 case.toml 的 status 与 safe_hal_status 字段，作为
# "已登记的上板状态" 与 "是否已走 MIR 安全路径" 的依据。
#
# 用法：
#   .\tools\check-case-safety.ps1                      # 统计 + 清单
#   .\tools\check-case-safety.ps1 -Module gpio        # 只看某模块
#   .\tools\check-case-safety.ps1 -AsMarkdown         # 输出可粘贴的 Markdown 表格
#   .\tools\check-case-safety.ps1 -FailOnUnsafe        # 存在非 SAFE-HAL 即退出码 1

param(
    [string]$Module = '',
    [switch]$AsMarkdown,
    [switch]$FailOnUnsafe,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$caseRoot = Join-Path $projectRoot 'app\hardware-tests'

if (-not (Test-Path -LiteralPath $caseRoot)) {
    throw "case root not found: $caseRoot"
}

$caseTomls = Get-ChildItem -LiteralPath $caseRoot -Recurse -Filter 'case.toml' -File
if ($Module) {
    $caseTomls = $caseTomls | Where-Object { $_.FullName -match [regex]::Escape("\$Module\") }
}

$rows = @()
foreach ($tomlFile in $caseTomls) {
    $caseDir = $tomlFile.Directory
    $module = $caseDir.Parent.Name
    $name = $caseDir.Name
    $mainRs = Join-Path $caseDir.FullName 'src\main.rs'

    # case.toml 字段
    $toml = Get-Content -LiteralPath $tomlFile.FullName -Raw
    $status = 'unknown'
    if ($toml -match '(?m)^status\s*=\s*"([^"]+)"') { $status = $Matches[1] }
    $safeHalStatus = ''
    if ($toml -match '(?m)^safe_hal_status\s*=\s*"([^"]+)"') { $safeHalStatus = $Matches[1] }

    # main.rs 分类
    # 注：`pub extern "C" fn rust_main()` 是固件入口的 ABI 导出（编译器要求），
    # 不是 unsafe FFI 调用；真正的 FFI 是 `unsafe extern "C" { ... }` 声明块、
    # `unsafe { f28035_*(...) }` 调用块和裸指针。
    $content = ''
    if (Test-Path -LiteralPath $mainRs) { $content = Get-Content -LiteralPath $mainRs -Raw }

    $usesHal = $content -match 'f28035_safe_hal'
    $hasFfiBlock = $content -match 'unsafe\s+extern\s+"C"\s*\{'
    $hasUnsafeCall = $content -match '\bunsafe\s*\{'
    $hasBarePtr = $content -match '\bas\s+\*(const|mut)\b'
    $hasFfi = $hasFfiBlock -or $hasUnsafeCall -or $hasBarePtr

    if (-not $usesHal -and -not $hasFfi) { $class = 'scaffold' }
    elseif ($usesHal -and -not $hasFfi) { $class = 'SAFE-HAL' }
    elseif ($usesHal -and $hasFfi) { $class = 'mixed' }
    else { $class = 'direct-FFI' }

    $rows += [pscustomobject]@{
        Module = $module
        Case   = $name
        Status = $status
        SafeHal = $safeHalStatus
        Class  = $class
    }
}

if (-not $Quiet) {
    Write-Output ('Total cases: {0}' -f $rows.Count)
    Write-Output ''
    Write-Output '==== Classification ===='
    $rows | Group-Object Class | Sort-Object Name | ForEach-Object {
        Write-Output ('  {0,-10} {1}' -f $_.Name, $_.Count)
    }

    $verifiedHal = @($rows | Where-Object { $_.Class -eq 'SAFE-HAL' -and $_.SafeHal -ne '' }).Count
    Write-Output ''
    Write-Output ('SAFE-HAL with safe_hal_status recorded (real MIR route): {0}' -f $verifiedHal)

    if ($AsMarkdown) {
        Write-Output ''
        Write-Output '==== Markdown table ===='
        Write-Output '| Module | Case | status | safe_hal_status | class |'
        Write-Output '|---|---|---|---|---|'
        foreach ($r in ($rows | Sort-Object Module, Case)) {
            Write-Output ('| {0} | {1} | {2} | {3} | {4} |' -f $r.Module, $r.Case, $r.Status, $r.SafeHal, $r.Class)
        }
    }
    else {
        Write-Output ''
        Write-Output '==== Detail ===='
        $rows | Sort-Object Module, Case | Format-Table Module, Case, Status, SafeHal, Class -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() }
    }
}

if ($FailOnUnsafe) {
    $unsafe = @($rows | Where-Object { $_.Class -ne 'SAFE-HAL' })
    if ($unsafe.Count -gt 0) {
        Write-Output ''
        Write-Output ("FAIL: {0} case(s) are not SAFE-HAL" -f $unsafe.Count)
        exit 1
    }
    Write-Output ''
    Write-Output 'PASS: all cases are SAFE-HAL'
}
