# tools/_internal/image-stamp.ps1
#
# 烧录映像新鲜度门禁（fail-closed buildstamp）。
#
# 问题背景：切 features（如 rust-api 的 one-file-main）或改源码后，固定 .out
# 别名（build\user-main\user_main_ram.out、build\user-main-flash\user_main_flash.out、
# build\mir-*\*_mir.out 等）可能仍是旧输入的产物；带 -SkipBuild 的上板脚本会
# 把旧程序原样加载/重链接进目标板。
#
# 机制：构建脚本在链接+审计成功后调用 Set-ImageStamp，把"全部构建输入的
# 指纹"写进 <image>.buildstamp；加载/重链接脚本调用 Assert-ImageFresh，
# 指纹不匹配即抛错（宁可拒绝加载，也不静默烧旧程序）。
# 显式覆盖：-Force / -AllowStale 参数负责逃生门，绕过时必须显式声明。
#
# 用法（构建方）：
#   . (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
#   $key = New-ImageKey -Label 'user_main_ram' -Tags @{ features='one-file-main' } `
#            -Files @($source, $bridge, ...) -Compiler $Compiler
#   ... 链接 + 审计成功后：
#   Set-ImageStamp -Image $out -Key $key
#
# 用法（上板方）：
#   Assert-ImageFresh -Image $out -Key $key -Context 'verify-user-main-flash'
#
# 指纹内容：文件 SHA256（缺席记 ABSENT）、编译器 path|size|mtime、任意 tag。
# 算法与 verify-case-ram.ps1 的 buildstamp 一致（该机制已在 RAM case 验证中
# 使用），stamp 为纯文本 SHA256 十六进制串。

function Get-ImageFileFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'ABSENT' }
    $item = Get-Item -LiteralPath $Path
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($item.FullName)
        try {
            return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
        } finally {
            $stream.Dispose()
        }
    } catch {
        # 无法读取（权限/占用）也视为过期，不得假装新鲜
        return "UNREADABLE|$($item.FullName)"
    } finally {
        $sha.Dispose()
    }
}

function Get-ToolchainFingerprint {
    # 编译器标识：路径+长度+mtime 足以识别换机/升级；不做全文哈希以免
    # 每次 assert 都读几十 MB 编译器 exe。
    param([Parameter(Mandatory = $true)][string]$Compiler)
    if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) { return "MISSING|$Compiler" }
    $item = Get-Item -LiteralPath $Compiler
    return "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
}

function New-ImageKey {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [hashtable]$Tags,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files,
        [string]$Compiler = ''
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("label=$Label")
    if ($Compiler) { $lines.Add("toolchain=$(Get-ToolchainFingerprint -Compiler $Compiler)") }
    if ($Tags) {
        foreach ($name in ($Tags.Keys | Sort-Object)) {
            $lines.Add("tag:$name=$($Tags[$name])")
        }
    }
    foreach ($path in $Files) {
        $lines.Add("$path=$(Get-ImageFileFingerprint -Path $path)")
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $payload = ($lines -join "`n")
        return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Test-ImageStamp {
    param([Parameter(Mandatory = $true)][string]$Image, [Parameter(Mandatory = $true)][string]$Key)
    $stamp = "$Image.buildstamp"
    if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $stamp -PathType Leaf)) { return $false }
    return ((Get-Content -LiteralPath $stamp -Raw).Trim() -eq $Key)
}

function Set-ImageStamp {
    param([Parameter(Mandatory = $true)][string]$Image, [Parameter(Mandatory = $true)][string]$Key)
    if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Cannot stamp a missing image: $Image" }
    Set-Content -LiteralPath "$Image.buildstamp" -Value $Key -NoNewline -Encoding ASCII
    Write-Output "IMAGE_STAMP=OK $Image"
}

function Assert-ImageFresh {
    param(
        [Parameter(Mandatory = $true)][string]$Image,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Context,
        # 显式逃生门：调用方加 -AllowStale（或上游 -Force）时跳过断言，
        # 但必须打印醒目警告，保证"加载旧程序"永远是有意识的行为。
        [switch]$AllowStale
    )
    if (Test-ImageStamp -Image $Image -Key $Key) {
        Write-Output "IMAGE_FRESH=PASS $Image ($Context)"
        return
    }
    if ($AllowStale) {
        Write-Warning ('IMAGE_STALE_ALLOWED: loading unverified image {0} ({1}). The .out may be from an older source/feature set - you explicitly allowed this.' -f $Image, $Context)
        return
    }
    $reason = if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) {
        'image does not exist'
    } elseif (-not (Test-Path -LiteralPath "$Image.buildstamp" -PathType Leaf)) {
        'no buildstamp (image predates the freshness gate or was built by hand)'
    } else {
        'buildstamp mismatch — source/feature/toolchain inputs changed since the image was linked'
    }
    throw (@"
STALE IMAGE REFUSED ($Context): $Image
Reason: $reason
Fix: rebuild without -SkipBuild (or run the build script) so the image is
relinked from current inputs, then retry. To override knowingly, pass -Force.
"@)
}
