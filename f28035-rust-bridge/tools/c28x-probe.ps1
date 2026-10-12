# c28x-probe.ps1 — run the C28x llc on one .ll and print everything it said.
#
# Small debugging companion to verify-llvm-c28x.ps1. Both go through
# Invoke-NativeCapture (llvm-c28x-env.ps1), so rc / stdout / stderr come back
# raw — without PowerShell's ErrorRecord formatting, which wraps long
# diagnostics mid-word and hides the message you are actually looking for.
#
# Usage:
#   .\tools\c28x-probe.ps1 -Src in.ll -Mode asm
#   .\tools\c28x-probe.ps1 -Src in.ll -Mode obj -Obj out.o -DumpObject
#   .\tools\c28x-probe.ps1 -Src in.ll -Mode raw -LlcArgs '-debug-only=isel'
#
# -Mode asm  : emit TI assembly (uses the MCInstPrinter; no encoder involved)
# -Mode obj  : emit a relocatable object (exercises MCCodeEmitter + applyFixup)
# -Mode raw  : pass -LlcArgs through untouched
#
# NOTE on naming: PowerShell variable names are case-INsensitive, so a local
# "$dump" silently *is* the [switch]$Dump parameter, and assigning a
# PSCustomObject to it fails with argument-transformation error. Every local
# here avoids naming that is a case-variant of a parameter.
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [ValidateSet('asm', 'obj', 'raw')][string]$Mode = 'asm',
    [string]$Obj = '',
    [string[]]$LlcArgs = @(),
    [switch]$DumpObject,
    [switch]$Verify  # add -verify-machineinstrs
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

if (-not (Test-Path $Src)) { throw "source not found: $Src" }

$extra = @()
if ($Verify) { $extra += '-verify-machineinstrs' }

switch ($Mode) {
    'asm' { $extra += @('-filetype=asm', $Src, '-o', '-') }
    'obj' {
        if (-not $Obj) { $Obj = Join-Path $env:TEMP ([IO.Path]::GetFileNameWithoutExtension($Src) + '.o') }
        $extra += @('-filetype=obj', $Src, '-o', $Obj)
    }
    'raw' { $extra += @($Src) + $LlcArgs }
}
# -LlcArgs is appended last so ad-hoc flags survive in every mode.
$extra += $LlcArgs

$res = Invoke-Llc -Arguments $extra
Write-Host "rc = $($res.ExitCode)  $(Format-Rc $res.ExitCode)"
if ($res.StdOut.Trim()) {
    Write-Host '--- stdout ---'
    Write-Host $res.StdOut.TrimEnd()
}
if ($res.StdErr.Trim()) {
    Write-Host '--- stderr ---'
    Write-Host $res.StdErr.TrimEnd()
}

if ($Mode -eq 'obj' -and $res.ExitCode -eq 0 -and $DumpObject) {
    $dumpRes = Invoke-NativeCapture $C28xToolchain.Objdump @('-s', '-j', '.text', $Obj)
    Write-Host '--- objdump -s -j .text ---'
    Write-Host $dumpRes.StdOut.TrimEnd()
    if ($dumpRes.StdErr.Trim()) { Write-Host $dumpRes.StdErr.TrimEnd() }
}

exit $res.ExitCode
