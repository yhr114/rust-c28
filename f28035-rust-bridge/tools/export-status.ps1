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
        Verification = $values.verification
    }
}

$output = Join-Path $projectRoot 'all_cases_status.csv'
$pendingOutput = Join-Path $projectRoot 'all_cases_status.pending.csv'
$records | Sort-Object Category, Name | Export-Csv -LiteralPath $pendingOutput -NoTypeInformation

try {
    Move-Item -LiteralPath $pendingOutput -Destination $output -Force
    Write-Output "Exported $($records.Count) cases to $output"
} catch {
    Write-Warning "Could not replace $output because it is open in another program."
    Write-Output "Current $($records.Count)-case snapshot is available at $pendingOutput"
}
