param(
    [Parameter(Mandatory = $true)]
    [string]$MainFile,

    [string]$OutputName = 'user_project'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')

$projectRoot = Split-Path -Parent $PSScriptRoot
$MainFile = (Resolve-Path -LiteralPath $MainFile).Path
$userMainRs = Join-Path $projectRoot 'crates\rust-api\src\user_main.rs'
$libRs = Join-Path $projectRoot 'crates\rust-api\src\lib.rs'
$asmOut = Join-Path $projectRoot "build\user-project\$OutputName.asm"

Write-Host "=== Build user project ==="
Write-Host "main.rs: $MainFile"
Write-Host "asm out: $asmOut"
Write-Host ""

Write-Host "[1/3] Copy main.rs -> user_main.rs ..."
Copy-Item $MainFile $userMainRs -Force

Write-Host "[2/3] Generate assembly ..."
& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile $libRs `
    -AssemblyFile $asmOut `
    -OnlyExport 'rust_user_main'
if ($LASTEXITCODE -ne 0) { throw "MIR generation failed" }

Write-Host "[3/3] Done!"
Write-Host ""
Write-Host "Assembly: $asmOut"
Write-Host ""
Write-Host "Next: link with CGT to .out"