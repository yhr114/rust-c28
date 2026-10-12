# sync-and-build-c28x.ps1
#
# Copies the working copy of the C28x backend
#   <repo>\backend\llvm-c28x\  ->  D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x\
# and rebuilds `llc` (and optionally llvm-objdump) with ninja.
#
# Why a script and not an ad-hoc copy: the in-tree build reads from the D: tree,
# so *every* source edit must be mirrored before building, otherwise ninja
# happily reports "no work to do" and you debug a stale binary. Keeping the
# mirror in one place makes that impossible to forget.
#
# Usage:
#   & .\tools\sync-and-build-c28x.ps1              # copy + ninja llc
#   & .\tools\sync-and-build-c28x.ps1 -Targets 'llc','llvm-objdump'
#   & .\tools\sync-and-build-c28x.ps1 -WhatIfOnly  # show the copy plan only

param(
    [string[]]$Targets = @('llc'),
    [string]$Source = '',
    [string]$Dest = '',
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

# CRITICAL: ninja spawns llvm-tblgen / clang / link through cmd.exe, and those
# binaries are UCRT imports that need the api-ms-win-crt-* forwarders on PATH.
# Without this, any change to a .td file fails every tblgen step with
# "exit code -1073741515 (0xC0000135 / STATUS_DLL_NOT_FOUND)" and ninja reports
# only "FAILED: ... C28xGen*.inc" with no compiler diagnostic. Dot-sourcing the
# env script is what makes `.td` edits rebuildable.
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path $repo 'backend\llvm-c28x' }
if (-not $Dest) { $Dest = 'D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x' }
$buildDir = 'D:\c28x-toolchain\build-c28x-clang'
$ninja = 'E:\Qt\Tools\Ninja\ninja.exe'

if (-not (Test-Path $Source)) { throw "C28x source not found: $Source" }
if (-not (Test-Path $Dest)) { throw "In-tree target not found: $Dest" }

# Mirror every tracked source file. `Test-Path -PathType Leaf` keeps directories
# out (we never need to create dirs; the in-tree layout already matches).
$files = Get-ChildItem -Path $Source -Recurse -File |
    Where-Object { $_.Extension -in '.cpp', '.h', '.td', '.txt', '.inc' }

$copied = 0
$skipped = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Source.Length).TrimStart('\')
    $dst = Join-Path $Dest $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path $dstDir)) {
        if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    }
    $same = (Test-Path $dst) -and
            ((Get-Item $dst).Length -eq $f.Length) -and
            ((Get-FileHash $dst).Hash -eq (Get-FileHash $f.FullName).Hash)
    if ($same) { $skipped++; continue }
    if ($WhatIfOnly) { Write-Host "WOULD COPY $rel" }
    else { Copy-Item -LiteralPath $f.FullName -Destination $dst -Force }
    $copied++
}

Write-Host "sync: $copied copied, $skipped unchanged (of $($files.Count))"
if ($WhatIfOnly) { return }

if (-not (Test-Path $ninja)) { throw "ninja not found at $ninja" }

Push-Location $buildDir
try {
    & $ninja @Targets 2>&1 | ForEach-Object { Write-Host $_ }
    $rc = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($rc -ne 0) { throw "ninja failed with exit code $rc" }
Write-Host "build: OK -> $(Join-Path $buildDir 'bin')"
