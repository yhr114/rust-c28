param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$manifest = Join-Path $PSScriptRoot 'rust-to-ti-c\Cargo.toml'
$targetDirectory = Join-Path $PSScriptRoot 'rust-to-ti-c\target-host'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $Cargo)) {
    throw "Cargo not found: $Cargo"
}

Push-Location (Split-Path -Parent $projectRoot)
try {
    & $Cargo run --quiet --manifest-path $manifest --target x86_64-pc-windows-msvc --target-dir $targetDirectory -- $InputFile $OutputFile
    if ($LASTEXITCODE -ne 0) {
        throw "Rust-to-C translation failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
