#Requires -Version 5.1
param([string]$Cargo = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'build\user-main\reject'
$mir = Join-Path $outDir 'unsupported.mir.txt'
$asm = Join-Path $outDir 'unsupported.asm'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
        -InputFile (Join-Path $root 'tests\fixtures\unsupported_user_main.rs') `
        -OutputFile $mir -AssemblyFile $asm -Cargo $Cargo `
        -OnlyExport rust_user_main -RustcArguments '-Zmir-opt-level=4' *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $mir -PathType Leaf) -or
    -not (Select-String -LiteralPath $mir -Pattern 'c28x-codegen: unsupported rust_user_main' -Quiet)) {
    throw 'Unsupported user main was not rejected by the MIR backend.'
}
Write-Output 'USER_MAIN_UNSUPPORTED_ATOMIC_REJECT=PASS'

$divMir = Join-Path $outDir 'unsupported-div.mir.txt'
$divAsm = Join-Path $outDir 'unsupported-div.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
        -InputFile (Join-Path $root 'tests\fixtures\unsupported_user_main_div.rs') `
        -OutputFile $divMir -AssemblyFile $divAsm -Cargo $Cargo `
        -OnlyExport rust_user_main -RustcArguments '-Zmir-opt-level=4' *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $divMir -PathType Leaf) -or
    -not (Select-String -LiteralPath $divMir -Pattern 'c28x-codegen: unsupported rust_user_main' -Quiet)) {
    throw 'Unsupported user arithmetic was not rejected by the MIR backend.'
}
Write-Output 'USER_MAIN_UNSUPPORTED_ARITHMETIC_REJECT=PASS'
