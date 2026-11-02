# Reproducible global LLVM enum entries used by C28xSubtarget.cpp.
param([string]$LlvmSource = 'D:\c28x-toolchain\llvm-project-23.1.1.src\llvm')
$ErrorActionPreference = 'Stop'
$path = Join-Path $LlvmSource 'include\llvm\IR\RuntimeLibcalls.td'
$text = [IO.File]::ReadAllText($path)
$definitions = [ordered]@{ c28x_memcpy='MEMCPY'; c28x_memmove='MEMMOVE'; c28x_memset='MEMSET'; c28x_memcmp='MEMCMP'; c28x_bcmp='BCMP' }
$present = 0
foreach ($entry in $definitions.GetEnumerator()) {
    if ($text -match ('(?m)^def\s+' + $entry.Key + '\s*:')) {
        if ($text -notmatch ('(?m)^def\s+' + $entry.Key + '\s*:\s*RuntimeLibcallImpl<' + $entry.Value + '>;\s*$')) {
            throw "Unexpected LLVM declaration for $($entry.Key); do not make C28x helpers global defaults"
        }
        $present++
    }
}
if ($present -eq $definitions.Count) { Write-Host 'C28x memory libcall declarations already present (non-default)'; return }
if ($present) { throw 'Partial C28x memory libcall declarations; repair explicitly before building' }
$anchor = '// Stack Protector Fail'
if (-not $text.Contains($anchor)) { throw 'RuntimeLibcalls.td anchor changed' }
$block = "// C28x logical-byte helpers; selected explicitly by C28xSubtarget.`n// Keep standard targets on their existing defaults.`n"
foreach ($entry in $definitions.GetEnumerator()) { $block += "def $($entry.Key) : RuntimeLibcallImpl<$($entry.Value)>;`n" }
$text = $text.Replace($anchor, ($block + "`n" + $anchor))
[IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
Write-Host 'Added C28x non-default memory libcall declarations'
