# 环境搭建指南 (SETUP.md)

本指南说明如何在一台新电脑上从零搭建 F28035 Rust-C28x 开发环境，完成从源码编译到上板验证的全流程。

## 目录

- [项目概述](#项目概述)
- [硬件要求](#硬件要求)
- [第一步：安装基础软件](#第一步安装基础软件)
- [第二步：克隆仓库](#第二步克隆仓库)
- [第三步：构建支持 c28x 的 rustc（PATH A 核心）](#第三步构建支持-c28x-的-rustcpath-a-核心)
- [第四步：配置工具链路径](#第四步配置工具链路径)
- [第五步：构建和验证项目](#第五步构建和验证项目)
- [第六步（可选）：构建 LLVM c28x 后端（PATH B）](#第六步可选构建-llvm-c28x-后端path-b)
- [目录结构](#目录结构)
- [常见问题](#常见问题)

---

## 项目概述

本项目为 TI TMS320F28035（C28x 内核）MCU 提供 Rust 开发支持，包含两条技术路线：

- **PATH A（当前可用）**：`backend/c28x-mir/` — 读取 rustc 的 MIR，直接生成 C28x 汇编，已在 XDS100v2 真机验证
- **PATH B（研究中）**：`backend/llvm-c28x/` — 从零实现的 LLVM C28x 后端，目标是让 rustc 直接编译任意 Rust 到 C28x 机器码
- **应用开发路径**：`sdk/` + `app/` — Rust 写应用，经 `tools/rust-to-ti-c` 翻译成 C，再用 TI cl2000 编译链接

## 硬件要求

| 项目 | 说明 |
|---|---|
| 开发板 | TI TMS320F28035 系列（如 LAUNCHXL-F28027/F28035 自定义板） |
| 调试器 | XDS100v2（或 XDS110），用于 JTAG 烧录和 RAM 调试 |
| 电脑 | Windows 10/11 x64，建议 16GB+ 内存（编译 rustc 较耗资源） |

> 纯编译不需要开发板，只有上板验证才需要 XDS100v2。

---

## 第一步：安装基础软件

### 1.1 Git

下载安装：https://git-scm.com/download/win

安装时勾选 "Add Git to PATH"。

### 1.2 Rust (rustup)

下载安装：https://rustup.rs/

安装后切换到 nightly 并安装必要组件：

```powershell
rustup toolchain install nightly
rustup default nightly
rustup component add rustc-dev rust-src llvm-tools-preview rustfmt
```

验证：
```powershell
rustc --version
cargo --version
```

### 1.3 LLVM-MinGW（编译 rustc 需要的 GNU 环境）

下载：https://github.com/mstorsjo/llvm-mingw/releases

下载 `llvm-mingw-<version>-msvcrt-x86_64.zip`，解压到例如 `C:\llvm-mingw`，将 `bin` 目录加入系统 PATH。

验证：
```powershell
clang --version
```

### 1.4 TI C2000 CGT 编译器

下载：https://www.ti.com/tool/C2000-CGT

安装后记住 `cl2000.exe` 的路径，例如：
`C:\ti\ti-cgt-c2000_25.11.1.LTS\bin\cl2000.exe`

验证：
```powershell
& "C:\ti\ti-cgt-c2000_25.11.1.LTS\bin\cl2000.exe" --version
```

### 1.5 Code Composer Studio (CCS)（上板验证用）

下载：https://www.ti.com/tool/CCSTUDIO

安装时勾选 C2000 器件支持。CCS 提供：
- `dss.bat` — 脚本调试接口（验证脚本用）
- `xds100serial.exe` — XDS100 串口工具
- XDS100v2 驱动

### 1.6 Ninja 和 CMake（构建 LLVM/rustc 需要）

```powershell
winget install Ninja-build.Ninja
winget install Kitware.CMake
```

验证：
```powershell
ninja --version
cmake --version
```

---

## 第二步：克隆仓库

```powershell
git clone https://github.com/yhr114/rust-c28.git
cd rust-c28\f28035-rust-bridge
```

仓库核心结构：
```
f28035-rust-bridge/
├── app/                  # 例程源码（firmware、examples、146个硬件测试）
├── sdk/                  # 底层库（safe-hal + C ABI 桥）
├── crates/               # 编译器研究路径的 Rust crate
├── backend/
│   ├── c28x-mir/         # PATH A：MIR → C28x 汇编后端
│   └── llvm-c28x/        # PATH B：LLVM C28x 后端
├── tools/                # 构建/烧录/验证脚本（300+）
├── platform/             # TI C/asm 平台支持
├── docs/                 # 架构/安全/ABI 文档
└── rust-toolchain.toml   # Rust 工具链版本锁定
```

---

## 第三步：构建支持 c28x 的 rustc（PATH A 核心）

这一步会从源码构建一个打了 c28x target 补丁的 rustc。仓库已提供自动化脚本。

### 3.1 准备源码和补丁

```powershell
powershell -File tools\prepare-rustc-c28x.ps1
```

脚本自动完成：
1. clone `rust-lang/rust` 源码到 `D:\c28x-toolchain\rust-c28x`（可通过 `-RustSource` 指定路径）
2. 检出与当前 nightly 匹配的 commit
3. 应用 `backend/llvm-c28x/rustc-patches/0001-add-c28x-target.patch`
4. 初始化 `src/llvm-project` 子模块
5. 将 `backend/llvm-c28x/` 以 Junction 方式挂载到 `llvm/lib/Target/C28x`
6. 应用 LLVM triple 补丁
7. 写入 `bootstrap.toml`（Windows GNU 构建配置）

> 如果已有 Rust 源码，加 `-SkipClone` 跳过 clone：
> ```powershell
> powershell -File tools\prepare-rustc-c28x.ps1 -RustSource D:\rust-src -SkipClone
> ```

### 3.2 构建 stage1 rustc

```powershell
powershell -File tools\build-rustc-c28x.ps1
```

> 这一步耗时较长（30-60 分钟，取决于 CPU 和内存），需要保持网络畅通。

构建完成后，rustc 在：
```
<RustSource>\x86_64-pc-windows-gnu\stage1\bin\rustc.exe
```

### 3.3 验证 c28x target

```powershell
& "<RustSource>\x86_64-pc-windows-gnu\stage1\bin\rustc.exe" --print target-list | Select-String c28x
```

应输出 `c28x-none-elf`。

---

## 第四步：配置工具链路径

所有构建脚本通过 `tools/toolchain.ps1` 集中管理路径。有两种配置方式：

### 方式一：环境变量（推荐，不改源码）

```powershell
# TI 编译器
$env:TI_CGT_CL2000 = "C:\ti\ti-cgt-c2000_25.11.1.LTS\bin\cl2000.exe"

# CCS 调试脚本
$env:TI_CCS_DSS_BAT = "C:\ti\ccs\ccs_base\scripting\bin\dss.bat"

# XDS100 串口工具
$env:TI_XDS100SERIAL = "C:\ti\ccs\ccs_base\common\uscif\xds100serial.exe"

# Cargo
$env:CARGO_BIN = "$env:USERPROFILE\.cargo\bin\cargo.exe"

# LLVM 源码根（PATH B 用）
$env:LLVM_PROJECT_ROOT = "D:\llvm-project-llvmorg-23.1.1"

# Rust c28x 源码根
$env:RUST_C28X_SOURCE = "D:\c28x-toolchain\rust-c28x"
```

建议将这些写入系统环境变量，或在每次开发前执行一个 `env.ps1` 脚本。

### 方式二：直接修改 toolchain.ps1

编辑 `tools/toolchain.ps1`，修改默认路径：

```powershell
$script:Toolchain.Compiler = 'C:\ti\ti-cgt-c2000_25.11.1.LTS\bin\cl2000.exe'
$script:Toolchain.Dss      = 'C:\ti\ccs\ccs_base\scripting\bin\dss.bat'
# ... 其余同理
```

---

## 第五步：构建和验证项目

### 5.1 应用开发路径（Rust → C → cl2000）

```powershell
# 新建测试用例
powershell -File tools\new-case.ps1 -Category gpio -Name gpio_output_toggle_basic

# 构建（Rust → C → 编译 → 链接）
powershell -File tools\build-case.ps1 -Case gpio/gpio_output_toggle_basic

# RAM 模式 JTAG 验证（需要 XDS100v2 连接开发板）
powershell -File tools\verify-case-ram.ps1 -Case gpio/gpio_output_toggle_basic

# 查看所有用例状态
powershell -File tools\report-status.ps1
```

### 5.2 MIR 研究路径（PATH A）

```powershell
# 构建控制环示例（ePWM + ADC + Timer0）
powershell -File tools\build-mir-control-loop.ps1

# 烧录到 Flash 并真机验证
powershell -File tools\flash-and-verify-mir-control-loop.ps1

# 单文件应用（编辑 app/src/main.rs 后构建）
powershell -File tools\build-user-main-flash.ps1
powershell -File tools\program-user-main-flash.ps1 -ConfirmFlashErase
```

### 5.3 Safe HAL 用例验证

```powershell
powershell -File tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_output_basic
powershell -File tools\verify-safe-hal-case-ram.ps1 -Case adc/adc_sample_basic
powershell -File tools\verify-safe-hal-case-ram.ps1 -Case epwm/epwm_cmp_basic
powershell -File tools\verify-safe-hal-case-ram.ps1 -Case integration/safe_hal_control_loop
```

---

## 第六步（可选）：构建 LLVM c28x 后端（PATH B）

如果需要研究 LLVM 后端路线：

### 6.1 独立构建 LLVM 后端

```bash
cd backend/llvm-c28x

# Linux/Mac（bootstrap.sh 自动 clone LLVM + 挂载后端 + CMake + Ninja）
LLVM_SRC=/path/to/llvm-project ./bootstrap.sh
```

Windows 下手动执行：
```powershell
# 1. 下载 LLVM 23.1.1 源码
git clone --depth 1 --branch llvmorg-23.1.1 https://github.com/llvm/llvm-project.git D:\llvm-project

# 2. 打 triple 补丁
git -C D:\llvm-project apply backend\llvm-c28x\llvm-patches\0001-llvm23-register-c28x-triple.patch

# 3. 挂载 C28x 后端
New-Item -ItemType Junction -Path D:\llvm-project\llvm\lib\Target\C28x -Target (Resolve-Path backend\llvm-c28x)

# 4. CMake 配置 + 构建
cmake -G Ninja -B D:\llvm-build -S D:\llvm-project\llvm `
  -DLLVM_TARGETS_TO_BUILD="X86" `
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="C28x" `
  -DCMAKE_BUILD_TYPE=Release
ninja -C D:\llvm-build llc
```

### 6.2 验证 LLVM 后端

```powershell
& D:\llvm-build\bin\llc.exe -mtriple=c28x-ti-none backend\llvm-c28x\test\CodeGen\hello.ll -o -
```

---

## 目录结构

```
f28035-rust-bridge/
├── app/                          # 例程源码
│   ├── firmware/                 # C 启动跳板（调用 rust_main）
│   ├── examples/                 # 完整 Rust 主程序示例
│   └── hardware-tests/           # 146 个外设测试用例
├── sdk/                          # 底层库
│   ├── f28035-safe-hal/          # Rust HAL（PAC + 类型安全 HAL + FFI）
│   └── c-abi/                    # C ABI 桥（155 个窄接口）
├── crates/                       # 编译器研究路径 crate
│   ├── rust-api/                 # MIR 后端输入 PAC/HAL
│   ├── c28x-rt/                  # Runtime/startup
│   ├── c28x-rt-macros/           # #[entry] 过程宏
│   ├── panic-c28x/               # Panic handler
│   └── rust-targets/             # 目标测试程序
├── backend/                      # 编译器后端
│   ├── c28x-mir/                 # PATH A：MIR → 汇编（~5700 行）
│   └── llvm-c28x/                # PATH B：LLVM 后端（37 文件，190 指令）
│       ├── llvm-patches/         # LLVM triple 注册补丁
│       ├── rustc-patches/        # rustc c28x target 补丁
│       └── test/                 # CodeGen/Rust 测试用例
├── tools/                        # 构建/烧录/验证脚本
│   ├── build-case.ps1            # 应用路径构建
│   ├── build-mir-*.ps1           # MIR 路径构建（150+ 外设）
│   ├── verify-*.ps1              # 验证脚本（200+）
│   ├── flash-and-verify-*.ps1    # 烧录+验证
│   ├── prepare-rustc-c28x.ps1    # rustc 源码准备
│   ├── build-rustc-c28x.ps1      # rustc 构建
│   ├── toolchain.ps1             # 工具链路径集中管理
│   └── rust-to-ti-c/             # Rust → C 翻译器
├── platform/                     # TI 平台支持
│   ├── vendor/ti/f2803x/         # C2000Ware 头文件
│   ├── firmware/                 # 链接脚本 .cmd
│   └── runtime/                  # C28x 汇编运行时
├── docs/                         # 文档
│   ├── ARCHITECTURE.md           # 架构说明
│   ├── SAFETY.md                 # 安全边界
│   ├── ABI_FREEZE.md             # ABI 冻结约定
│   └── ...
├── .cargo/config.toml            # Cargo 构建配置（c28x target）
├── rust-toolchain.toml           # Rust nightly 组件锁定
└── SETUP.md                      # 本文档
```

---

## 常见问题

### Q: 编译 rustc 报错 "linker not found"

确保 LLVM-MinGW 的 `bin` 目录已加入 PATH，且 `bootstrap.toml` 使用的是 GNU 工具链。检查：
```powershell
where.exe clang
where.exe lld
```

### Q: `cl2000.exe` 找不到

确认 TI CGT 已安装，并在 `tools/toolchain.ps1` 或环境变量 `TI_CGT_CL2000` 中设置了正确路径。

### Q: XDS100v2 连接失败

1. 确认 CCS 已安装且 XDS100v2 驱动正常
2. 检查设备管理器中是否有 "XDS100 Class" 设备
3. 确认开发板上电且 JTAG 接线正确
4. 尝试用 CCS 自带的 `xds100serial.exe` 测试连接

### Q: rustc 构建太慢/内存不足

- 确保内存 ≥ 16GB，建议 32GB
- 可在 `bootstrap.toml` 中设置 `jobs = 4` 限制并行度
- 第一次构建后备份 `stage1/bin/`，后续可直接解压使用

### Q: 如何更新 rustc 补丁

当 `backend/llvm-c28x/rustc-patches/` 中的补丁更新后：
```powershell
cd <RustSource>
git apply --reverse backend\llvm-c28x\rustc-patches\0001-add-c28x-target.patch
git apply backend\llvm-c28x\rustc-patches\0001-add-c28x-target.patch
powershell -File tools\build-rustc-c28x.ps1
```

### Q: PATH A 和 PATH B 有什么区别

- **PATH A（c28x-mir）**：外挂工具，读取 rustc MIR 生成汇编，轻量快速，已真机验证，但只支持有限的 Rust 语法
- **PATH B（llvm-c28x）**：内嵌 LLVM 后端，理论上支持任意 Rust，但工程量大，当前骨架阶段

详细对比见 `docs/ARCHITECTURE.md`。

---

## 参考文档

- `README.md` — 项目总览和快速开始
- `docs/ARCHITECTURE.md` — 完整架构说明
- `docs/SAFETY.md` — 安全边界和审计
- `docs/ABI_FREEZE.md` — ABI 冻结约定
- `backend/llvm-c28x/README.md` — LLVM 后端状态
- `backend/llvm-c28x/PATCHING_RUSTC.md` — rustc 补丁说明
