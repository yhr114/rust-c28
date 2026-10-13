# convert-llvm-to-ti-asm.ps1
# 把 LLVM 生成的 C28x 汇编转换成 TI 汇编器认识的格式

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$lines = Get-Content $InputFile
$result = @()

# 文件开头加段定义
$result += '    .sect "text"'
$result += ''

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # 空行
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        $result += ''
        continue
    }

    # 分离注释
    $code = $trimmed
    $comment = ''
    $idx = $trimmed.IndexOf(';')
    if ($idx -ge 0) {
        $code = $trimmed.Substring(0, $idx).Trim()
        $comment = $trimmed.Substring($idx)
    }

    # 伪指令行（. 开头）
    if ($code.StartsWith('.')) {
        # 保留 .global，其他伪指令加注释
        if ($code -match '^\.global\s+(.+)$') {
            $sym = $Matches[1]
            $newLine = "    .global $sym"
        }
        else {
            $newLine = "; $code (ignored)"
        }
        if ($comment) { $newLine += " $comment" }
        $result += $newLine
        continue
    }

    # 标签行（: 结尾）
    if ($code.EndsWith(':')) {
        $newLine = $code.ToUpper()
        if ($comment) { $newLine += " $comment" }
        $result += $newLine
        continue
    }

    # 指令行 - 全部转大写
    if ($code.Length -gt 0) {
        $newLine = "    " + $code.ToUpper()
        if ($comment) { $newLine += " $comment" }
        $result += $newLine
        continue
    }

    # 其他
    $result += $trimmed
}

$result | Out-File -FilePath $OutputFile -Encoding ascii

Write-Host "Done: $InputFile -> $OutputFile"
Write-Host "Total lines: $($result.Count)"
