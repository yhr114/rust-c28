param([switch]$Verify)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$sdkRoot = (Resolve-Path -LiteralPath (Join-Path $here '..\..\f28035-rust-bridge')).Path
. (Join-Path $sdkRoot 'tools\toolchain.ps1')

# Cargo checks this project against the real SDK API on the host.
$previousTarget = $env:CARGO_BUILD_TARGET
try {
    $env:CARGO_BUILD_TARGET = 'x86_64-pc-windows-msvc'
    & $Toolchain.Cargo check --manifest-path (Join-Path $here 'Cargo.toml') --target x86_64-pc-windows-msvc
    if ($LASTEXITCODE -ne 0) { throw 'case1 Cargo type check failed.' }
} finally {
    $env:CARGO_BUILD_TARGET = $previousTarget
}

# The SDK's supported Rust subset is translated in place; case1/src/main.rs
# is never copied into crates/rust-api.
$buildScript = Join-Path $sdkRoot 'tools\verify-case-ram.ps1'
$options = @{
    ExternalCaseRoot = $here
    VerifierScript = Join-Path $here 'verify.js'
}
if (-not $Verify) { $options.SkipVerify = $true }
& $buildScript @options
