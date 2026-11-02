# patch-llvm-triple-c28x.ps1 — 给 LLVM 树打 C28x Triple 补丁（幂等）
# 实证来源：LLVM 23.1.1 本机构建（2026-09-16，llc 实跑通过）。
# 作用：让 llvm::Triple 认识 c28x 架构——打印/解析/LLVM 名映射/
#       对象格式 ELF/指针位宽 32（FROZEN ABI，见 docs/PATH_B.md）。
# 用法:  powershell -File tools\patch-llvm-triple-c28x.ps1 [-LlvmRoot <llvm-project 根>]
param(
    [string]$LlvmRoot = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $LlvmRoot) { $LlvmRoot = $Toolchain.LlvmRoot }

$ErrorActionPreference = 'Stop'
$tripleH = Join-Path $LlvmRoot 'llvm\include\llvm\TargetParser\Triple.h'
$tripleCpp = Join-Path $LlvmRoot 'llvm\lib\TargetParser\Triple.cpp'
if (-not (Test-Path $tripleH) -or -not (Test-Path $tripleCpp)) {
    throw "LLVM tree not found at $LlvmRoot (Triple.h / Triple.cpp missing)"
}

$changed = 0
function Apply([string]$path, [string]$old, [string]$new, [string]$what) {
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains($old)) {
        [System.IO.File]::WriteAllText($path, $text.Replace($old, $new))
        Write-Host ("  patched: $what") -ForegroundColor Green
        $script:changed++
    } elseif ($text.Contains($new)) {
        Write-Host ("  already: $what") -ForegroundColor DarkGray
    } else {
        throw "patch anchor not found: $what (context changed?)"
    }
}

Write-Host "==> Triple.h: ArchType 枚举加 c28x"
Apply $tripleH `
    "    bpfeb,       // eBPF or extended BPF or 64-bit BPF (big endian)`n    csky,        // CSKY: csky" `
    "    bpfeb,       // eBPF or extended BPF or 64-bit BPF (big endian)`n    c28x,        // C28x: TI C2000 C28x (experimental, out-of-tree backend)`n    csky,        // CSKY: csky" `
    'Triple.h ArchType::c28x'

Write-Host "==> Triple.cpp: getArchTypeName"
Apply $tripleCpp `
    "  case bpfel:`n    return `"bpfel`";`n  case csky:" `
    "  case bpfel:`n    return `"bpfel`";`n  case c28x:`n    return `"c28x`";`n  case csky:" `
    'getArchTypeName c28x'

Write-Host "==> Triple.cpp: getArchTypePrefix"
Apply $tripleCpp `
    "  case ve:`n    return `"ve`";`n  case csky:" `
    "  case ve:`n    return `"ve`";`n  case c28x:`n    return `"c28x`";`n  case csky:" `
    'getArchTypePrefix c28x'

Write-Host "==> Triple.cpp: getArchTypeForLLVMName"
Apply $tripleCpp `
    "      .Case(`"ve`", ve)`n      .Case(`"csky`", csky)" `
    "      .Case(`"ve`", ve)`n      .Case(`"c28x`", c28x)`n      .Case(`"csky`", csky)" `
    'getArchTypeForLLVMName c28x'

Write-Host "==> Triple.cpp: parseArch"
Apply $tripleCpp `
    "          .Case(`"ve`", Triple::ve)`n          .Case(`"wasm32`", Triple::wasm32)`n          .Case(`"wasm64`", Triple::wasm64)`n          .Case(`"csky`", Triple::csky)" `
    "          .Case(`"ve`", Triple::ve)`n          .Case(`"wasm32`", Triple::wasm32)`n          .Case(`"wasm64`", Triple::wasm64)`n          .Case(`"c28x`", Triple::c28x)`n          .Case(`"csky`", Triple::csky)" `
    'parseArch c28x'

Write-Host "==> Triple.cpp: getObjectFormat -> ELF"
Apply $tripleCpp `
    "  case Triple::xtensa:`n    return Triple::ELF;" `
    "  case Triple::xtensa:`n  case Triple::c28x:`n    return Triple::ELF;" `
    'getObjectFormat ELF'

Write-Host "==> Triple.cpp: getArchPointerBitWidth -> 32 (FROZEN ABI)"
Apply $tripleCpp `
    "  case llvm::Triple::xtensa:`n    return 32;" `
    "  case llvm::Triple::xtensa:`n  case llvm::Triple::c28x:`n    return 32;" `
    'getArchPointerBitWidth 32'

Write-Host ''
Write-Host ("patch-llvm-triple-c28x: $changed 处已应用，其余已存在（幂等）。") -ForegroundColor Cyan
Write-Host '重新构建 llc:  cd <build>; mingw32-make llc -j8' -ForegroundColor DarkGray
