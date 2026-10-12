# self-check.ps1 - 批量跑所有 verified-via-mir case
# 用法: .\tools\self-check.ps1

$ErrorActionPreference = 'Continue'
$toolsDir = $PSScriptRoot

$scripts = Get-ChildItem $toolsDir -Filter 'verify-mir-*.ps1' | Sort-Object Name
Write-Output "Found $($scripts.Count) verify scripts`n"

$pass = 0
$fail = 0
$failures = @()

foreach ($s in $scripts) {
    $name = $s.Name -replace 'verify-mir-', '' -replace '.ps1', ''
    Write-Output -NoNewline "  $name ... "
    try {
        $out = & $s.FullName 2>&1
        $result = $out | Select-String 'RESULT: PASS'
        if ($result) {
            Write-Output "PASS"
            $pass++
        } else {
            Write-Output "FAIL"
            $fail++
            $failures += $name
        }
    } catch {
        Write-Output "ERROR"
        $fail++
        $failures += "$name (exception)"
    }
}

Write-Output "`n===== Summary ====="
Write-Output "Total: $($scripts.Count)"
Write-Output "PASS:  $pass"
Write-Output "FAIL:  $fail"
if ($failures.Count -gt 0) {
    Write-Output "`nFailed cases:"
    $failures | ForEach-Object { Write-Output "  - $_" }
}