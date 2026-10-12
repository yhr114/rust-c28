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

if (-not (Test-Path -LiteralPath $Cargo)) {
    throw "Cargo not found: $Cargo"
}

& $Cargo run --quiet --manifest-path $manifest -- $InputFile $OutputFile --emit=ti-asm
if ($LASTEXITCODE -ne 0) {
    throw "Rust-to-TI-assembly translation failed with exit code $LASTEXITCODE"
}
