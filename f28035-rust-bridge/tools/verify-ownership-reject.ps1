#Requires -Version 5.1
param([string]$Cargo = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'build\ownership-gpio34'
$mir = Join-Path $out 'negative.mir.txt'
$asm = Join-Path $out 'negative.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
        -InputFile (Join-Path $root 'crates\ownership-gpio34\src\lib.rs') `
        -OutputFile $mir -AssemblyFile $asm -Cargo $Cargo `
        -OnlyExport rust_once_acquire `
        -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature="ownership-negative"') *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $mir) -or
    -not (Select-String -LiteralPath $mir -Pattern 'c28x-codegen: unsupported rust_once_acquire' -Quiet)) {
    throw 'Changed ownership compare_exchange was not rejected by the MIR backend.'
}
Write-Output 'OWNERSHIP_ACTION_REJECT=PASS'

$applicationMir = Join-Path $out 'negative-application.mir.txt'
$applicationAsm = Join-Path $out 'negative-application.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
        -InputFile (Join-Path $root 'crates\ownership-gpio34\src\lib.rs') `
        -OutputFile $applicationMir -AssemblyFile $applicationAsm -Cargo $Cargo `
        -OnlyExport rust_ownership_application `
        -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature="application-negative"') *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $applicationMir) -or
    -not (Select-String -LiteralPath $applicationMir -Pattern 'c28x-codegen: unsupported rust_ownership_application' -Quiet)) {
    throw 'Changed ownership application branch was not rejected by the MIR backend.'
}
Write-Output 'OWNERSHIP_BRANCH_REJECT=PASS'

$gpioMir = Join-Path $out 'negative-gpio.mir.txt'
$gpioAsm = Join-Path $out 'negative-gpio.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
        -InputFile (Join-Path $root 'crates\ownership-gpio34\src\lib.rs') `
        -OutputFile $gpioMir -AssemblyFile $gpioAsm -Cargo $Cargo `
        -OnlyExport rust_gpio34_set_low `
        -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature="gpio-negative"') *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $gpioMir) -or
    -not (Select-String -LiteralPath $gpioMir -Pattern 'c28x-codegen: unsupported rust_gpio34_set_low' -Quiet)) {
    throw 'Changed GPIO34 output action was not rejected by the MIR backend.'
}
Write-Output 'OWNERSHIP_GPIO_ACTION_REJECT=PASS'
