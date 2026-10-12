# Content identity of the external LLVM inputs used to link rustc.
# No timestamp changes and no compiler invocation.
function Get-C28xLlvmFingerprint([string]$BuildDirectory) {
    $config = Join-Path $BuildDirectory 'bin\llvm-config.exe'
    if (-not (Test-Path -LiteralPath $config)) { throw "Missing LLVM config: $config" }
    $libraries = @(Get-ChildItem -LiteralPath (Join-Path $BuildDirectory 'lib') -File |
        Where-Object { $_.Extension -in '.a', '.lib', '.dll' } | Sort-Object Name)
    if ($libraries.Count -eq 0) { throw 'No LLVM libraries found for fingerprinting' }
    $inputs = @((Get-Item -LiteralPath $config)) + $libraries
    $inputs += @(Get-ChildItem -LiteralPath (Join-Path $BuildDirectory 'bin') -Filter '*LLVM*.dll' -File)
    $lines = foreach ($inputFile in $inputs) {
        $inputFile.FullName + ':' + (Get-FileHash -LiteralPath $inputFile.FullName -Algorithm SHA256).Hash
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).Replace('-', '')
    } finally { $sha.Dispose() }
}
