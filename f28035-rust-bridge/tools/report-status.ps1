$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifests = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app\hardware-tests') `
    -Filter case.toml -File -Recurse

$records = foreach ($manifest in $manifests) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $manifest.FullName) {
        if ($line -match '^([a-z_]+)\s*=\s*"(.*)"\s*$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    [pscustomobject]@{
        Category = $values.category
        Name = $values.name
        Status = $values.status
    }
}

$records | Group-Object Status | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ Status = $_.Name; Count = $_.Count }
} | Format-Table -AutoSize

Write-Output "Total: $($records.Count)"
