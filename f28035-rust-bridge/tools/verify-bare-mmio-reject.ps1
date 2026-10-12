#Requires -Version 5.1
param([string]$Cargo = '')

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'crates\bare-gpio34\tests\unsupported_branch.rs'
$output = Join-Path $root 'build\bare-gpio34\unsupported.mir.txt'
$assembly = Join-Path $root 'build\bare-gpio34\unsupported.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $source `
        -OutputFile $output -AssemblyFile $assembly -Cargo $Cargo `
        -RustcArguments '-Zmir-opt-level=4' *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $output) -or
    -not (Select-String -LiteralPath $output -Pattern 'c28x-codegen: unsupported rust_bare_gpio34_low' -Quiet)) {
    throw 'Unsupported branching MMIO was not rejected by the MIR backend.'
}
Write-Output 'UNSUPPORTED_MMIO_REJECT=PASS'

$safeSource = Join-Path $root 'sdk\f28035-safe-hal\src\lib.rs'
$safeOutput = Join-Path $root 'build\safe-gpio34\unsupported.mir.txt'
$safeAssembly = Join-Path $root 'build\safe-gpio34\unsupported.asm'
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $safeSource `
        -OutputFile $safeOutput -AssemblyFile $safeAssembly -Cargo $Cargo `
        -OnlyExport rust_safe_gpio34_low `
        -RustcArguments @('-Zmir-opt-level=4', '--cfg', 'feature="bare-mmio"', `
            '--cfg', 'feature="bare-mmio-negative"') *> $null
} catch {
    $rejected = $true
}
if (-not $rejected -or -not (Test-Path -LiteralPath $safeOutput) -or
    -not (Select-String -LiteralPath $safeOutput -Pattern 'c28x-codegen: unsupported rust_safe_gpio34_low' -Quiet)) {
    throw 'Changed Safe HAL GPIO action was not rejected by the MIR backend.'
}
Write-Output 'SAFE_HAL_ACTION_REJECT=PASS'
