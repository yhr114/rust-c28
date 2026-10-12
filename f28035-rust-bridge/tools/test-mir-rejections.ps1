param(
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $projectRoot 'backend\c28x-mir\Cargo.toml'
$outputDirectory = Join-Path $projectRoot 'build\mir\negative'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

function Test-RejectedExport {
    param(
        [string]$SourceName,
        [string]$ExpectedSymbol,
        [string]$OutputStem
    )
    $inputFile = Join-Path $projectRoot "tests\mir\$SourceName"
    $env:C28X_MIR_OUTPUT = Join-Path $outputDirectory "$OutputStem.mir.txt"
    $env:C28X_MIR_ASM_OUTPUT = Join-Path $outputDirectory "$OutputStem.asm"
    try {
        $output = @(& $Cargo run --manifest-path $manifest -- $inputFile --edition=2024 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item Env:C28X_MIR_OUTPUT -ErrorAction SilentlyContinue
        Remove-Item Env:C28X_MIR_ASM_OUTPUT -ErrorAction SilentlyContinue
    }
    if ($exitCode -eq 0) {
        throw "Unsupported exported MIR function was accepted: $ExpectedSymbol"
    }
    if (-not ($output -match [regex]::Escape($ExpectedSymbol))) {
        $output | ForEach-Object { Write-Output $_ }
        throw "MIR rejection did not identify $ExpectedSymbol."
    }
}

Test-RejectedExport -SourceName 'unsupported_control_loop.rs' -ExpectedSymbol 'unsupported_control_loop' -OutputStem 'unsupported-control-loop'
Write-Output 'MIR_UNSUPPORTED_EXPORT_TEST=PASS'
exit 0
