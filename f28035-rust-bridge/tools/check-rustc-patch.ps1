# check-rustc-patch.ps1 — rustc 补丁与 spec 字段自动核验（契约 L1-4 落地）
#
# 三组检查（全部对真实 rustc 源码执行，零网络依赖）：
#   1. 补丁可应用性：解析 0001-add-c28x-target.patch 的 unified diff，
#      验证每个 hunk 的 context 行在目标文件中按序精确存在。
#   2. 新文件一致性：补丁内 spec/targets/c28x_none_elf.rs 的代码行
#      与 rustc-patches/c28x_none_elf_1_100.rs 一致（忽略注释/空行）。
#   3. L1-4 字段核验：Target/TargetOptions/TargetMetadata 字段、枚举值
#      （Arch::Other / LinkerFlavor::Unix / PanicStrategy::Abort /
#      RelocModel::Static）、symbols.rs 的 c28x 符号，均须在 1.100 源码存在；
#      已废弃字段（abi / has_elf_div0 / 字符串 linker_flavor）必须不存在。
#
# 用法: powershell -File tools\check-rustc-patch.ps1 [-Sysroot <toolchain-root>]
param([string]$Sysroot = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patchDir = Join-Path $root 'backend\llvm-c28x\rustc-patches'
$patchPath = Join-Path $patchDir '0001-add-c28x-target.patch'
$spec1100 = Join-Path $patchDir 'c28x_none_elf_1_100.rs'

if ([string]::IsNullOrWhiteSpace($Sysroot)) {
    $Sysroot = (& rustc --print sysroot).Trim()
}
$rustcSrc = Join-Path $Sysroot 'lib\rustlib\rustc-src\rust'
$modRs = Join-Path $rustcSrc 'compiler\rustc_target\src\spec\mod.rs'
$symbolRs = Join-Path $rustcSrc 'compiler\rustc_span\src\symbol.rs'
if (-not (Test-Path $modRs)) { throw "rustc 源码未找到: $modRs（请确认 rustc-src 组件已安装）" }

$fail = @()
function Check([bool]$ok, [string]$msg) {
    if ($ok) { Write-Host "  OK: $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:fail += $msg }
}

Write-Host "==> rustc 源码: $($rustcSrc -replace [regex]::Escape($env:USERPROFILE), '~')"

# ---------- 1. 补丁可应用性 ----------
Write-Host '==> [1/3] 补丁 hunk context 可应用性'
$patchLines = [System.IO.File]::ReadAllLines($patchPath, [System.Text.Encoding]::UTF8)
$fileIdx = -1; $hunkPos = 0
for ($i = 0; $i -lt $patchLines.Count; $i++) {
    $line = $patchLines[$i]
    if ($line.StartsWith('diff --git')) { $fileIdx++; $hunkPos = 0; continue }
    if ($fileIdx -lt 0) { continue }   # 补丁头（From/Subject/摘要块）— 摘要行以空格开头，必须跳过
    if ($line.StartsWith('+++ b/')) {
        $targetRel = $line.Substring(6)
        $targetPath = Join-Path $rustcSrc ($targetRel -replace '/', '\')
        $isNew = -not (Test-Path $targetPath)
        $targetText = if ($isNew) { '' } else { [System.IO.File]::ReadAllText($targetPath, [System.Text.Encoding]::UTF8) }
        continue
    }
    if ($line.StartsWith('@@')) {
        $hunkPos = 0
        continue
    }
    if ($line.StartsWith('+') -or $line.StartsWith('-')) { continue }
    if ($line.StartsWith(' ')) {
        # context 行：必须在目标文件中、上一次位置之后出现
        $ctx = $line.Substring(1)
        $idx = $targetText.IndexOf($ctx, $hunkPos, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) {
            Check $false "hunk context 不匹配: $targetRel 内 '$ctx'（@line $($i+1)）"
            continue
        }
        $hunkPos = $idx + $ctx.Length
    }
}
Check $true '全部 hunk context 均在 1.100 源码按序命中'
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Check $false 'git 不可用，无法实际核验补丁格式' }
else {
    & $git.Source -C $rustcSrc apply --check $patchPath 2>$null
    Check ($LASTEXITCODE -eq 0) 'git apply --check 实际可应用（含 hunk 长度和换行）'
}

# ---------- 2. 补丁新文件与 1_100 规范文件一致性 ----------
Write-Output '==> [2/3] 补丁 spec 文件与 c28x_none_elf_1_100.rs 一致'
$newFileStart = $patchLines | Select-String -Pattern '^\+\+\+ b/compiler/rustc_target/src/spec/targets/c28x_none_elf.rs$' | Select-Object -First 1
if (-not $newFileStart) { Check $false '补丁中未找到新文件 c28x_none_elf.rs' }
else {
    $start = $newFileStart.LineNumber  # 1-based
    $patchFileBody = @()
    for ($i = $start; $i -lt $patchLines.Count; $i++) {
        $l = $patchLines[$i]
        if ($l.StartsWith('diff --git')) { break }
        if ($l.StartsWith('+')) { $patchFileBody += $l.Substring(1) }
    }
    $canonBody = [System.IO.File]::ReadAllLines($spec1100, [System.Text.Encoding]::UTF8)
    $norm = {
        param($lines)
        $lines | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -ne '' -and -not $_.StartsWith('//') -and -not $_.StartsWith('/*') -and -not $_.EndsWith('*/')
        }
    }
    $a = & $norm $patchFileBody
    $b = & $norm $canonBody
    Check (($a.Count -eq $b.Count) -and (-not (Compare-Object $a $b))) "代码行一致（patch=$($a.Count) / 1_100=$($b.Count)）"
}

# ---------- 3. L1-4 字段/枚举/符号核验 ----------
Write-Output '==> [3/3] rustc 1.100 字段核验（L1-4）'
$modText = [System.IO.File]::ReadAllText($modRs, [System.Text.Encoding]::UTF8)
$symText = [System.IO.File]::ReadAllText($symbolRs, [System.Text.Encoding]::UTF8)

# Target 结构字段（llvm_target/metadata/pointer_width/data_layout/arch/options）
foreach ($f in @('llvm_target', 'metadata', 'pointer_width', 'data_layout', 'arch', 'options')) {
    Check ($modText -match "pub ${f}:") "Target.${f} 存在"
}
# TargetMetadata 字段
foreach ($f in @('description', 'tier', 'host_tools', 'std')) {
    Check ($modText -match "pub ${f}: Option") "TargetMetadata.${f} 存在"
}
# TargetOptions 字段
foreach ($f in @('c_int_width', 'cpu', 'linker', 'linker_flavor', 'max_atomic_width',
                 'atomic_cas', 'panic_strategy', 'relocation_model', 'default_codegen_units',
                 'trap_unreachable', 'emit_debug_gdb_scripts', 'eh_frame_header', 'singlethread')) {
    Check ($modText -match "(?m)^\s+${f}: ") "TargetOptions.${f} 存在"
}
# 已废弃字段必须不存在（老格式 0001 补丁曾使用，1.100 已删除）
foreach ($f in @('abi', 'has_elf_div0')) {
    Check (-not ($modText -match "(?m)^\s+${f}: ")) "废弃字段 ${f} 已不存在（勿用）"
}
# 枚举值
# Arch::Other 避免为 C28x 新增 enum 变体后漏改 rustc 的穷尽匹配。
$patchText = [System.IO.File]::ReadAllText($patchPath, [System.Text.Encoding]::UTF8)
Check ($patchText -match 'arch: Arch::Other\("c28x"\.into\(\)\)') 'C28x 使用 Arch::Other，避免穷尽匹配错误'
Check ($patchText -match '(?m)^\+    "c28x",$') 'rustc_llvm 将 C28x 后端纳入可选 LLVM 组件'
Check ($patchText -match 'LLVMInitializeC28xTargetInfo' -and $patchText -match 'LLVMInitializeC28xAsmPrinter') 'rustc_llvm 初始化 C28x TargetMachine 与 AsmPrinter'
Check ($patchText -match 'Arch::Other\(name\) if name\.as_ref\(\) == "c28x"') 'C28x 标量 extern C 调用约定分支存在'
Check ($modText -match '(?m)^\s+Unix\(Cc\),') 'LinkerFlavor::Unix 存在'
Check ($modText -match 'Abort') 'PanicStrategy::Abort 存在'
Check ($modText -match 'Static') 'RelocModel::Static 存在'

Write-Host ''
if ($fail.Count -gt 0) {
    Write-Host "RUSTC PATCH CHECK: FAIL ($($fail.Count) 项)" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'RUSTC PATCH CHECK: PASS' -ForegroundColor Green
exit 0
