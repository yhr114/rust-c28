param(
    [string]$SourceCaseRoot = 'C:\Users\61987\Desktop\28035\fpga_delivery_28035\case_src'
)

$ErrorActionPreference = 'Stop'
$newCaseScript = Join-Path $PSScriptRoot 'new-case.ps1'

if (-not (Test-Path -LiteralPath $SourceCaseRoot -PathType Container)) {
    throw "Source case directory not found: $SourceCaseRoot"
}

$created = 0
$skipped = 0

foreach ($category in Get-ChildItem -LiteralPath $SourceCaseRoot -Directory | Sort-Object Name) {
    foreach ($case in Get-ChildItem -LiteralPath $category.FullName -Directory | Sort-Object Name) {
        $destination = Join-Path (Split-Path -Parent $PSScriptRoot) `
            "app\hardware-tests\$($category.Name)\$($case.Name)"

        if (Test-Path -LiteralPath $destination) {
            $skipped++
            continue
        }

        & $newCaseScript -Category $category.Name -Name $case.Name
        $created++
    }
}

Write-Output "Created: $created"
Write-Output "Skipped: $skipped"
