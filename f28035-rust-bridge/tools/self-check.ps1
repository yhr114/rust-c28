#Requires -Version 5.1
<#
.SYNOPSIS
  全量 MIR 验证编排：遍历 tools/mir-cases.json 中的每个 case，调用 verify-mir.ps1。

  真实运行（需要 TI 工具链 + XDS100v1 + JTAG 硬件）：
    .\tools\self-check.ps1
    .\tools\self-check.ps1 -Case spi_loopback        # 只跑一个
    .\tools\self-check.ps1 -SkipBuild                # 跳过构建（对象已存在时）

  静态自检（无需工具链/硬件，确认清单与文件一致性）：
    .\tools\self-check.ps1 -DryRun

  输出汇总表与退出码：0 = 全部 PASS（或 DryRun 全部 OK），非 0 = 有 FAIL/异常。
#>
param(
    [string]$Case = '',
    [switch]$DryRun,
    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml'
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\mir-common.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir = $PSScriptRoot
$manifest = Join-Path $ToolsDir 'mir-cases.json'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Manifest not found: $manifest. Run tools/_internal/gen-mir-manifest.py first."
}
$cases = Get-Content $manifest -Raw | ConvertFrom-Json

if ($Case) {
    if (-not $cases.cases.PSObject.Properties[$Case]) {
        throw "Unknown case '$Case'. Available: $($cases.cases.PSObject.Properties.Name -join ', ')"
    }
    $keys = @($Case)
} else {
    $keys = $cases.cases.PSObject.Properties.Name
}

$rows = @()
$summary = @{ PASS = 0; FAIL = 0; CUSTOM = 0; ERR = 0; DRY_OK = 0; DRY_BAD = 0 }

foreach ($key in $keys) {
    $entry = $cases.cases.$key
    if ($DryRun) {
        $problems = @()
        if ($entry.custom) {
            if (-not (Test-Path -LiteralPath (Join-Path $ToolsDir $entry.legacyBuild))) { $problems += "legacy build missing: $($entry.legacyBuild)" }
            if ($entry.legacyVerify -and -not (Test-Path -LiteralPath (Join-Path $ToolsDir $entry.legacyVerify))) { $problems += "legacy verify missing: $($entry.legacyVerify)" }
        } else {
            $hs = Join-Path $ProjectRoot $entry.build.harnessSrc
            if (-not (Test-Path -LiteralPath $hs)) { $problems += "harness C missing: $($entry.build.harnessSrc)" }
            $js = Join-Path $ToolsDir $entry.verify.js
            if (-not (Test-Path -LiteralPath $js)) { $problems += "verify js missing: $($entry.verify.js)" }
            if (-not $entry.build.outputDir -or -not $entry.build.rustObj -or -not $entry.verify.ramOut) { $problems += "manifest fields incomplete" }
        }
        if ($problems) {
            $summary.DRY_BAD++
            $rows += ("{0,-26} {1,-8} {2}" -f $key, $(if($entry.custom){'CUSTOM'}else{'STD'}), ($problems -join '; '))
        } else {
            $summary.DRY_OK++
            $rows += ("{0,-26} {1,-8} manifest + referenced files OK" -f $key, $(if($entry.custom){'CUSTOM'}else{'STD'}))
        }
        continue
    }

    # 真实运行
    if ($entry.custom) { $summary.CUSTOM++ }
    $out = @(& (Join-Path $ToolsDir 'verify-mir.ps1') -Case $key -SkipBuild:$SkipBuild -Compiler $Compiler -Dss $Dss -TargetConfig $TargetConfig 2>&1 | ForEach-Object { "$_" })
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -eq 0) {
        $summary.PASS++
        $rows += ("{0,-26} PASS" -f $key)
    } else {
        $summary.FAIL++
        $rows += ("{0,-26} FAIL (exit {1})" -f $key, $LASTEXITCODE)
    }
}

Write-Output ''
Write-Output '================ self-check summary ================'
if ($DryRun) {
    Write-Output ("  mode         : DryRun (static manifest/file check, no build/JTAG)")
    Write-Output ("  cases        : {0}" -f $keys.Count)
    Write-Output ("  OK           : {0}" -f $summary.DRY_OK)
    Write-Output ("  problems     : {0}" -f $summary.DRY_BAD)
} else {
    Write-Output ("  cases        : {0}" -f $keys.Count)
    Write-Output ("  PASS         : {0}" -f $summary.PASS)
    Write-Output ("  FAIL         : {0}" -f $summary.FAIL)
    Write-Output ("  delegated    : {0} (custom, ran legacy script)" -f $summary.CUSTOM)
}
Write-Output '==================================================='
if ($rows.Count -gt 0) {
    Write-Output ($rows -join "`n")
}

if ($DryRun) {
    exit $(if ($summary.DRY_BAD -eq 0) { 0 } else { 1 })
} else {
    exit $(if ($summary.FAIL -eq 0) { 0 } else { 1 })
}

