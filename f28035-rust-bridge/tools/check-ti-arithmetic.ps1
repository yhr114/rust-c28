param([string]$CC = 'D:\mingw64\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'target\arithmetic-host'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$exe = Join-Path $out 'arithmetic-host.exe'
$r = Invoke-NativeCapture $CC @('-std=c99', '-O2', '-Wall', '-Wextra',
    (Join-Path $root 'backend\llvm-c28x\test\Runtime\arithmetic-host.c'), '-o', $exe)
if ($r.ExitCode -ne 0) { throw "Host runtime compilation failed: $($r.StdErr)" }
$r = Invoke-NativeCapture $exe @()
Write-Host $r.StdOut
if ($r.ExitCode -ne 0) { throw "Host arithmetic differential test failed: $($r.StdErr)" }
