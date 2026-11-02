# Convert llc C28x assembly into TI cl2000 assembly.
#
# Three TI-vs-LLVM differences are handled here:
#   1. TI has no .cfi_* / .p2align in this flow.
#   2. .asciz is spelled .string.
#   3. **.space does not allocate anything in TI EABI assembly** (verified with
#      asm2000: three labels separated by `.space 2` all resolve to offset 0).
#      LLVM prints zero-initialized globals as `label:` + `.space N`, so a Rust
#      program with two or more statics would give them all the same address.
#      Each 16-bit word is emitted as `.field 0,16`, which does advance the
#      location counter.
param(
    [Parameter(Mandatory = $true)][string]$In,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Extern = @(),
    [switch]$AutoExternCalls
)
$ErrorActionPreference = 'Stop'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('    .sect ".text"')
$inputLines = @(Get-Content -LiteralPath $In)
$defined = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in $inputLines) {
    if ($line -match '^\s*([A-Za-z_.$][\w.$]*):') {
        [void]$defined.Add($Matches[1])
    }
}
$externSymbols = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($symbol in $Extern) {
    if ($symbol -notmatch '^[A-Za-z_.$][\w.$]*$') {
        throw "Invalid external symbol: $symbol"
    }
    if ($defined.Contains($symbol)) {
        throw "External symbol is already defined in this assembly: $symbol"
    }
    [void]$externSymbols.Add($symbol)
}
if ($AutoExternCalls) {
    foreach ($line in $inputLines) {
        if ($line -match '^\s*lcr\s+([A-Za-z_.$][\w.$]*)\s*(?:;.*)?$') {
            $symbol = $Matches[1]
            if (-not $defined.Contains($symbol)) {
                [void]$externSymbols.Add($symbol)
            }
        }
    }
}
foreach ($symbol in ($externSymbols | Sort-Object)) {
    # TI asm2000 rejects an unresolved call unless the caller declares it.
    $lines.Add("    .ref $symbol")
}

foreach ($line in $inputLines) {
    if ($line -match '^\s*\.(?:p2align|cfi_\w+)\b') { continue }
    if ($line -match '^\s*\.asciz\s+') {
        $lines.Add(($line -replace '\.asciz', '.string'))
        continue
    }
    if ($line -match '^\s*\.space\s+(\d+)\s*$') {
        $bytes = [int]$Matches[1]
        # `label:` + `.space N` is how llc prints a zero-initialized global.
        # Emit it as a TI .bss object instead: a plain label inside .text is
        # typed STT_FUNC, so the debugger reports the symbol's *address* rather
        # than its contents, and the object would also live in code memory.
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -match '^([A-Za-z_.$][\w.$]*):\s*$') {
            $sym = $Matches[1]
            $lines.RemoveAt($lines.Count - 1)
            # TI .usect sizes are in 16-bit words; llc reports bytes.  .usect
            # (not .bss) keeps the symbol in the same output section the RAM
            # linker script zero-fills, so startup clears it and the symbol is
            # typed as an object rather than a function.
            $allocWords = [math]::Ceiling($bytes / 2)
            $lines.Add("$sym`:    .usect `".bss`", $allocWords")
            continue
        }
        $words = [math]::Floor($bytes / 2)
        for ($i = 0; $i -lt $words; $i++) { $lines.Add('    .field 0,16') }
        if ($bytes % 2) { $lines.Add('    .field 0,8') }
        continue
    }
    $lines.Add($line)
}

Set-Content -LiteralPath $Out -Value $lines -Encoding ascii
