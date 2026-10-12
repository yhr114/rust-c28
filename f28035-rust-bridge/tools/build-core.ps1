# build-core.ps1 — Build core + compiler_builtins for c28x-none-elf using patched rustc.
# Usage:
#   . tools/llvm-c28x-env.ps1
#   powershell -File tools/build-core.ps1
#
# All output goes through Invoke-NativeCapture-style logging to a log file so
# stderr is not hard-wrapped by PowerShell.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$env:RUSTC = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$env:RUSTC_BOOTSTRAP = '1'
$env:CARGO_NET_OFFLINE = 'true'

$target = 'c28x-none-elf'
$proj = Join-Path $root 'test-minimal'
$logDir = Join-Path $root 'build-logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir 'build-core.log'

Set-Location $proj

Write-Host "RUSTC=$env:RUSTC"
Write-Host "target=$target"
Write-Host "log=$log"

$args = @(
  'build',
  '--target', $target,
  '-Zbuild-std=core,compiler_builtins',
  '-Zbuild-std-features=panic_immediate_abort',
  '-v'
)

# Use System.Diagnostics.Process to capture raw stderr (avoid PS wrapping).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cargo'
$psi.Arguments = ($args -join ' ')
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.WorkingDirectory = $proj

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
$errTask = $proc.StandardError.ReadToEndAsync()
$out = $proc.StandardOutput.ReadToEnd()
$err = $errTask.GetAwaiter().GetResult()
$proc.WaitForExit()
$rc = $proc.ExitCode

"=== STDOUT ===" | Out-File $log -Encoding utf8
$out | Out-File $log -Append -Encoding utf8
"=== STDERR ===" | Out-File $log -Append -Encoding utf8
$err | Out-File $log -Append -Encoding utf8
"=== EXIT CODE: $rc ===" | Out-File $log -Append -Encoding utf8

Write-Host "EXIT CODE: $rc"
Write-Host "---- STDERR (tail) ----"
($err -split "`n") | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }
exit $rc
