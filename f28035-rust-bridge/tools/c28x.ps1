param(
    [ValidateSet('build', 'test', 'run')]
    [string]$Command = 'build',
    [string]$Compiler = '',
    [string]$Cargo = '',
    [string]$Dss = '',
    [string]$TargetConfig
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Dss) { $Dss = $Toolchain.Dss }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'

switch ($Command) {
    'build' {
        & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1') -Compiler $Compiler -Cargo $Cargo
    }
    'test' {
        & $Cargo test --manifest-path (Join-Path (Split-Path -Parent $PSScriptRoot) 'crates\rust-api\Cargo.toml')
        if ($LASTEXITCODE -ne 0) { throw 'Safe HAL host tests failed.' }
        & (Join-Path $PSScriptRoot 'build-native-arithmetic.ps1') -Compiler $Compiler -Cargo $Cargo
        if ($LASTEXITCODE -ne 0) { throw 'C28x backend regression tests failed.' }
        & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1') -Compiler $Compiler -Cargo $Cargo
    }
    'run' {
        & (Join-Path $PSScriptRoot 'build-mir-control-loop.ps1') -Compiler $Compiler -Cargo $Cargo
        if ($LASTEXITCODE -ne 0) { throw 'MIR control-loop build failed.' }
        $flashArguments = @{
            Dss = $Dss
            SkipBuild = $true
        }
        if ($TargetConfig) { $flashArguments.TargetConfig = $TargetConfig }
        & (Join-Path $PSScriptRoot 'flash-and-verify-mir-control-loop.ps1') @flashArguments
    }
}

if ($LASTEXITCODE -ne 0) {
    throw "C28x $Command failed with exit code $LASTEXITCODE."
}
