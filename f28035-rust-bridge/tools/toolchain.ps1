# ============================================================
# tools/toolchain.ps1 — 工具链路径集中管理
# ============================================================
# 本文件定义所有脚本共用的工具链路径，消除散落在 60+ 脚本
# param 默认值里的硬编码绝对路径。
#
# 用法：在脚本开头 dot-source 本文件，再读取 $Toolchain 哈希表：
#   . (Join-Path $PSScriptRoot 'toolchain.ps1')
#   if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
#
# 优先级：环境变量 > 本文件默认值 > 脚本 param 显式传参。
# 换机 / 升级 CCS 时，只需改这里（或设置环境变量）。

# 环境变量约定（可选，未设置时用下方默认值）：
#   TI_CGT_CL2000        TI C2000 编译器 cl2000.exe 全路径
#   TI_CCS_DSS_BAT       CCS scripting 的 dss.bat 全路径
#   TI_XDS100SERIAL      xds100serial.exe 全路径
#   CARGO_BIN            cargo.exe 全路径
#   LLVM_PROJECT_ROOT    LLVM 源码根（PATH B 研究用）
#   RUST_C28X_SOURCE     rust-c28x 源码根（PATH B 研究用）

$script:Toolchain = @{}

$script:Toolchain.Compiler = if ($env:TI_CGT_CL2000) {
    $env:TI_CGT_CL2000
} else {
    'D:\ti\ccstheia141\ccs\tools\compiler\ti-cgt-c2000_22.6.1A23259\bin\cl2000.exe'
}

$script:Toolchain.Dss = if ($env:TI_CCS_DSS_BAT) {
    $env:TI_CCS_DSS_BAT
} else {
    'D:\ti\ccstheia141\ccs\ccs_base\scripting\bin\dss.bat'
}

$script:Toolchain.Xds100Serial = if ($env:TI_XDS100SERIAL) {
    $env:TI_XDS100SERIAL
} else {
    'D:\ti\ccstheia141\ccs\ccs_base\common\uscif\xds100serial.exe'
}

$script:Toolchain.Cargo = if ($env:CARGO_BIN) {
    $env:CARGO_BIN
} else {
    'C:\Users\61987\.cargo\bin\cargo.exe'
}

$script:Toolchain.LlvmRoot = if ($env:LLVM_PROJECT_ROOT) {
    $env:LLVM_PROJECT_ROOT
} else {
    'D:\llvm-project-llvmorg-23.1.1'
}

$script:Toolchain.RustSource = if ($env:RUST_C28X_SOURCE) {
    $env:RUST_C28X_SOURCE
} else {
    'D:\c28x-toolchain\rust-c28x'
}
