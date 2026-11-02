#Requires -Version 5.1
<#
.SYNOPSIS
  将 legacy build-mir-<key>.ps1 / verify-mir-<key>.ps1 改为 3 行转发器，指向通用脚本。

  这是 P5「脚本合并」的最后一步，但默认只预览（-WhatIf），不改动任何文件。
  确认通用脚本在真机 + JTAG 上把 136 个 case 全量跑通后，再带 -Apply 执行。

  行为（仅 -Apply 时）：
    - 标准 case：原脚本移动到 tools/_archive/legacy-mir/ 备份，原地写入 3 行转发器
      -> 调用 tools/build-mir.ps1 -Case <key>（或 verify-mir.ps1）。
    - 非标准 case（custom=true）：保持原脚本不动（通用脚本本身对这些 case 也是委托给
      原脚本，行为不变）。
    - 绝不删除任何文件；原内容完整保留在 _archive 里，可随时还原。

  用法：
    .\tools\retire-legacy-mir-scripts.ps1            # 预览，不改文件
    .\tools\retire-legacy-mir-scripts.ps1 -Apply     # 真正改写
#>
param(
    [switch]$Apply,
    [string]$ArchiveDir = (Join-Path $PSScriptRoot '_archive\legacy-mir')
)

$ErrorActionPreference = 'Continue'
$manifest = Join-Path $PSScriptRoot 'mir-cases.json'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Manifest not found: $manifest. Run tools/_internal/gen-mir-manifest.py first."
}
$cases = Get-Content $manifest -Raw | ConvertFrom-Json

$forwarderBuild = 'build-mir.ps1'
$forwarderVerify = 'verify-mir.ps1'

$total = 0
$would = if ($Apply) { 'APPLY' } else { 'WHATIF' }
Write-Output "[$would] retire legacy MIR scripts (archive-only, no deletion)"

foreach ($key in $cases.cases.PSObject.Properties.Name) {
    $entry = $cases.cases.$key
    foreach ($pair in @(
        @{ legacy = $entry.legacyBuild; generic = $forwarderBuild },
        @{ legacy = $entry.legacyVerify; generic = $forwarderVerify })) {
        $legacy = $pair.legacy
        $generic = $pair.generic
        if (-not $legacy) { continue }
        $src = Join-Path $PSScriptRoot $legacy
        if (-not (Test-Path -LiteralPath $src)) { continue }

        if ($entry.custom) {
            Write-Output ("  KEEP   {0}  (custom, left untouched)" -f $legacy)
            continue
        }

        $total++
        if (-not $Apply) {
            Write-Output ("  FORWARD {0} -> {1} -Case {2}" -f $legacy, $generic, $key)
            continue
        }

        # 备份原脚本
        $destDir = Join-Path $ArchiveDir (Split-Path -Parent $legacy)
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $backup = Join-Path $ArchiveDir $legacy
        Copy-Item -LiteralPath $src -Destination $backup -Force

        # 写 3 行转发器
        $content = @(
            "# Auto-generated forwarder -> tools/$generic (P5 merge). Original archived under _archive/legacy-mir/."
            "& (Join-Path `$PSScriptRoot '$generic') -Case '$key' @args"
        ) -join "`n"
        Set-Content -Path $src -Value $content -Encoding utf8

        Write-Output ("  DONE   {0} -> {1} -Case {2}  (backup: {3})" -f $legacy, $generic, $key, $backup)
    }
}

Write-Output ""
Write-Output ("Summary: {0} legacy script(s) would be/已被 turned into forwarders (custom kept as-is)." -f $total)
if (-not $Apply) {
    Write-Output "This was a preview. Re-run with -Apply to actually rewrite (originals archived, never deleted)."
}
