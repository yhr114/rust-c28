# rustc-wrapper.ps1 - cargo RUSTC_WRAPPER entry point (PowerShell).
#
# cargo invokes:  rustc-wrapper.cmd <real-rustc-path> <rustc-args...>
# The .cmd shim forwards here; PowerShell handles the long arg array natively
# (cmd.exe chokes on the 8k command-line limit once compiler_builtins emits
# hundreds of --check-cfg flags).
#
# Routing:
#   --target c28x-none-elf                       -> patched C28x rustc
#   --target x86_64-pc-windows-gnu (host probe) -> system MSVC rustc, --target stripped
#   no --target + .rs input (build script)        -> system MSVC rustc
#   no --target + probe (-vV / --print / `-`)    -> patched rustc
#
# The patched rustc's host std produces broken Windows exes
# (STATUS_ENTRYPOINT_NOT_FOUND), so it must not compile host-runnable binaries.

$ErrorActionPreference = 'Continue'

$Log = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\rustc-wrapper.log'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $Log)

$PatchedRustc = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$SystemRustc  = 'C:\Users\61987\.cargo\bin\rustc.exe'
$MingwBin     = 'D:\c28x-toolchain\rust-build-gcc14fix\x86_64-pc-windows-gnu\stage0-sysroot\lib\rustlib\x86_64-pc-windows-gnu\bin'

# $args[0] = real rustc path cargo passed; drop it.
$argsList = @($args[1..($args.Count - 1)])

$targetArg = ''
for ($i = 0; $i -lt $argsList.Count; $i++) {
  if ($argsList[$i] -eq '--target' -and $i + 1 -lt $argsList.Count) {
    $targetArg = $argsList[$i + 1]
  } elseif ($argsList[$i] -like '--target=*') {
    $targetArg = $argsList[$i].Substring('--target='.Length)
  }
}

$hasRsInput = $false
foreach ($a in $argsList) {
  if ($a -notlike '--*' -and $a -like '*.rs') { $hasRsInput = $true }
}

$isVV = $argsList -contains '-vV'

function Invoke-Rustc([string]$exe, [string[]]$passArgs, [switch]$PrependMingw) {
  if ($PrependMingw) { $env:PATH = "$MingwBin;$env:PATH" }
  & $exe @passArgs
  exit $LASTEXITCODE
}

if ($targetArg -ieq 'c28x-none-elf') {
  Add-Content -Path $Log -Value ("[c28x] " + ($argsList -join ' '))
  Invoke-Rustc $PatchedRustc $argsList -PrependMingw
}

if ($targetArg -ieq 'x86_64-pc-windows-gnu') {
  $newArgs = New-Object System.Collections.Generic.List[string]
  $skipNext = $false
  foreach ($a in $argsList) {
    if ($skipNext) { $skipNext = $false; continue }
    if ($a -eq '--target') { $skipNext = $true; continue }
    if ($a -like '--target=*') { continue }
    $newArgs.Add($a)
  }
  Add-Content -Path $Log -Value ("[host-gnu->msvc] " + ($newArgs -join ' '))
  Invoke-Rustc $SystemRustc $newArgs.ToArray()
}

if ($isVV) {
  Add-Content -Path $Log -Value ("[vv->patched] " + ($argsList -join ' '))
  Invoke-Rustc $PatchedRustc $argsList
}

if ($hasRsInput) {
  Add-Content -Path $Log -Value ("[host-build->msvc] " + ($argsList -join ' '))
  Invoke-Rustc $SystemRustc $argsList
}

Add-Content -Path $Log -Value ("[probe->patched] " + ($argsList -join ' '))
Invoke-Rustc $PatchedRustc $argsList
