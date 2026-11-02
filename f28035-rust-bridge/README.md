# f28035-rust-bridge

Rust on TI TMS320F28035 (C28x) — SDK（应用层 + 底层库）+ MIR/LLVM 编译器后端。

工程文档集中在 [路径 A](docs/path-a/PATH_A.md) 和 [路径 B](docs/PATH_B.md)。
每次修改都按 [维护规则](AGENTS.md) 同步更新相关路线文档，并在
[工作日志](WORK_LOG.md) 记录完成内容、过程事件、验证结果和遗留事项。

## What this is

This project brings Rust to the TI C2000 F28035 microcontroller, modeled after
the STM32 embedded Rust ecosystem (`stm32f1xx-hal` / `embedded-hal`).

工程由两条路径组成：

**当前主路径是 B-1：定制 rustc + 内置 C28x LLVM 后端 + TI 链接。**
新 Rust 应用、Cargo 接入和编译器能力完善统一走 B-1。旧 B-2 独立 `llc`
流水线已迁至同级 `f28035-rust-bridge-b2-archive/`，不再参与日常构建。先阅读
[B-1 主路径与操作入口](docs/PATH_B.md#b1-main)。
具体工具、文件职责、编译发布和验证命令见 [B-1 工具与文件手册](docs/PATH_B.md#b1-files)。
当前维护工作只推进 PATH B-1。现有 PATH A、Rust-to-C 与 MIR 内容保持原状；
除非后续明确提出，不处理其构建失败、用例迁移或优化事项。

1. **应用开发路径（sdk + app）**：`sdk/` 提供 Rust HAL（`f28035-safe-hal`）与
   C ABI 桥（`c-abi`，155 个窄接口）；`app/` 放例程源码（firmware 入口、
   examples、146 个硬件测试用例）。写新代码 = 在 `app/` 写 `main`，调用
   `sdk/` 底层，经 `tools/rust-to-ti-c` 翻译 + TI CGT 链接烧录。

2. **编译器研究路径（backend + crates）**：因为 C28x 没有官方 Rust target 和
   LLVM 后端，本项目自制了两套后端：
   - **PATH A（当前可用）**：`backend/c28x-mir/` 读取 rustc 的 MIR，
     生成手写 C28x 汇编（输入在 `crates/rust-api/`），已在 XDS100v2 真机验证。
   - **PATH B-1（当前主路径）**：定制 rustc 内置 `backend/llvm-c28x/`
     后端。Cargo 主样板直接使用 `.o` 并解包依赖/core/builtins 的 `.rlib`，
     专用脚本由 rustc 生成 `.obj`，均交 TI 链接。两者已有受限样板真机验证，
     不代表任意 Rust crate 已支持。
   - 共享 `backend/llvm-c28x/` 仍可用独立 `llc` 做机器码级开发测试，
     但标准 rustc 改 IR 再调用 `llc` 的旧 B-2 交付流水线已归档。

## Repository Layout

```
f28035-rust-bridge/
├── app/                     # 例程源码（唯一放例程的地方）
│   ├── firmware/            # main.c 最小 C 启动跳板（调用 rust_main）
│   ├── examples/            # 完整 Rust 主程序示例（adc-pwm-control）
│   └── hardware-tests/      # 146 个按外设分类的上板测试用例
│
├── sdk/                     # 底层库（应用开发路径的 SDK）
│   ├── f28035-safe-hal/     # Rust HAL：no_std PAC + 类型安全 HAL + FFI 声明
│   │   ├── src/pac.rs       # PAC: MmioBus, HostMmio, C28xMmio, registers
│   │   ├── src/lib.rs       # HAL: OutputPin/InputPin/Timer0/Adc/Pwm
│   │   └── src/arithmetic.rs
│   └── c-abi/               # C ABI 桥：f28035_bridge.c/.h（155 窄接口）
│
├── crates/                  # 编译器研究路径的 Rust crate
│   ├── rust-api/            # MIR 后端的输入 PAC/HAL（含 application.rs）
│   ├── c28x-rt/             # Runtime / startup（modeled after msp430-rt）
│   ├── c28x-rt-macros/      # Proc-macro crate: #[entry]
│   ├── panic-c28x/          # Panic handler
│   └── rust-targets/        # Target test programs（native-arithmetic, gpio*）
│
├── backend/                 # 编译器后端
│   ├── c28x-mir/            # Out-of-tree MIR backend（~1700 行 main.rs）
│   └── llvm-c28x/           # LLVM C28x backend（146 files）
│
├── platform/                # TI C / asm 平台支持
│   ├── vendor/ti/f2803x/    # TI C2000Ware headers + linker scripts
│   ├── firmware/            # 链接脚本 .cmd（F28035_EABI_sections 等）
│   └── runtime/             # C28x asm runtime（delay, byte runtime）
│
├── tools/                   # 构建、烧录、验证及共享 LLVM 后端工具
│   ├── build-case.ps1       # 应用路径：Rust case → C → 编译 → 链接
│   ├── verify-case-ram.ps1  # 应用路径：RAM-only JTAG 验证
│   ├── build-mir-*.ps1      # MIR 路径：rust-api → C28x asm → 链接
│   ├── verify-mir-*.ps1     # MIR 路径：汇编序列/真机验证
│   └── rust-to-ti-c/        # Rust → C 翻译器（应用路径核心）
├── docs/                    # 安全/ABI/迁移文档
├── build/                   # Generated firmware (.out, .hex, .asm)
├── tests/                   # DSS verification scripts
├── targetConfigs/           # CCS debugger target configurations
├── all_cases_status.csv     # 146 个用例状态导出
└── *.md
```

## Quick Start（应用开发路径）

写一个新用例，然后构建 + RAM 验证：

```powershell
.\tools\new-case.ps1 -Category gpio -Name gpio_output_toggle_basic
.\tools\build-case.ps1 -Case gpio/gpio_output_toggle_basic
.\tools\verify-case-ram.ps1 -Case gpio/gpio_output_toggle_basic
.\tools\report-status.ps1
```

Rust 应用只调用 `sdk/f28035-safe-hal` 暴露的安全 API；新外设先在
`sdk/c-abi/f28035_bridge.h` 增加窄接口，再实现到 `.c`。

## Quick Start（MIR 研究路径）

单文件 Rust 应用样板：只编辑 `app/src/main.rs`，运行
`& tools/run-user-main.ps1 -Verify`，以 TI CGT 链接 RAM `.out` 并做 JTAG
验证。目前支持已验证的 `u16` 运算、循环、条件分支、GPIO 读回和输出操作，
还不是任意 Rust 程序的通用后端。默认流程已从当前 C bridge 源码重新构建，
并在 RAM/JTAG 上通过；
具体边界见 [路径 A 文档中的单文件实验](docs/path-a/PATH_A.md#a-9)。

同一份 `app/src/main.rs` 现在还可用 `tools/build-user-main-flash.ps1`
生成独立的 Flash `.out`，RAM 测试不变。Flash 写入是单独的显式操作
`tools/program-user-main-flash.ps1 -ConfirmFlashErase`，会先备份当前
user Flash 并擦写 sector A；断电重新上电后用
`tools/verify-user-main-flash.ps1` 只加载符号检查启动。构建通过不等于
板上 Flash 或断电启动已验证。

```powershell
# Build (generates firmware)
.\tools\build-mir-control-loop.ps1

# Flash + verify on real hardware (XDS100v2 connected)
.\tools\flash-and-verify-mir-control-loop.ps1 -SkipBuild

# Verify app-registered Safe HAL bridge cases over RAM/JTAG
.\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_output_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_output_readback_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_toggle_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case gpio/gpio_direction_switch_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case adc/adc_sample_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case epwm/epwm_cmp_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case timer/timer0_periodic_basic
.\tools\verify-safe-hal-case-ram.ps1 -Case integration/safe_hal_control_loop
```

### Legacy GPIO34 Flash pilot

The older GPIO34 scripts have RAM-only linkage and should not be used as
evidence of a persistent Flash image. Use the one-file Flash build and guarded
programming flow above for new work. GPIO34/GPIO37 must be strapped for
boot-to-Flash during reset. See
[路径 A 文档中的硬件恢复记录](docs/path-a/PATH_A.md#a-7) for the read-only CSM evidence,
memory-map correction, and safety checks.

## Architecture

完整说明见 [路径 A](docs/path-a/PATH_A.md) 与 [路径 B](docs/PATH_B.md)。
路径 A 汇总应用开发、安全审计和迁移记录；路径 B 汇总 LLVM、ABI、B-1
工具链和验证流程。旧 B-2 资料只在归档目录中保留。

## Current Status (verified on hardware)

| Component | Status |
|---|---|
| SDK Rust HAL（safe-hal） | ✅ 53 host unit tests + 15 doc tests passing |
| SDK C ABI bridge | ✅ 155 narrow interfaces |
| 硬件测试用例 | ✅ 146 个（verified 29 / compiled 54 / scaffold 63） |
| MIR MMIO lowering（5 variants） | ✅ Imm/Acc/Modify/WriteU32/ReadIndirect |
| EALLOW/EDIS auto-wrap | ✅ |
| MIR Safe HAL GPIO sweep | ✅ RAM/JTAG: GPIO0..34 + GPIO39..44 PASS；GPIO35..38 为当前 JTAG 占用脚 |
| App-registered Safe HAL cases | ✅ 7 GPIO bridge cases + 3 ADC/ePWM/Timer single cases + 1 integration bridge |
| Real hardware (XDS100v2) | ✅ TBPRD=4095, CMPA=ADC, tracking_error=0 |
| LLVM C28x backend | ✅ 146 files；`llc` 出 C28x asm/obj，机器码回归与 TI 链接通过 |
| rustc target patch | ✅ 补丁与构建脚本在 `f28035-rust-bridge-b1/backend/llvm-c28x/rustc-patches/` |
| core porting guide | ✅ in [路径 B 的 core 移植章节](docs/PATH_B.md#b-12) |

## What "working" means today

- 应用路径：Rust case 源码（`app/hardware-tests/*/src/main.rs`）经
  `tools/rust-to-ti-c` 翻译为 C，与 `sdk/c-abi` 大 bridge 链接，cl2000 编译
  后由 JTAG 烧录/验证（`build-case.ps1` / `verify-case-ram.ps1`）。
- MIR 路径：`crates/rust-api` 的函数 MIR 被 `backend/c28x-mir` 识别并生成
  C28x 汇编，链接 TI CGT 后烧录或 RAM 加载，F28035 运行 ePWM/Timer0/ADC
  控制环，并已完成 GPIO Safe HAL sweep 的非 JTAG 引脚全量验证。
- 桥接样板：`gpio_output_basic`、`gpio_output_readback_basic`、
  `gpio_toggle_basic`、`gpio_direction_switch_basic`、`gpio2_3_low`、
  `gpio30_low`、`gpio_mux_basic` 已作为 app case 登记，但验证命令走
  `tools/verify-safe-hal-case-ram.ps1`，即 app case 管理 + Safe HAL MIR
  后端构建，而不是旧 Rust-to-C translator。
- 单项外设样板：`adc/adc_sample_basic`、`epwm/epwm_cmp_basic`、
  `timer/timer0_periodic_basic` 已拆出并完成 RAM/JTAG PASS，分别验证 ADC
  SOC0 sample、ePWM1A TBPRD/CMPA 和 Timer0 10 ms periodic interrupt。
- 集成样板：`integration/safe_hal_control_loop` 已覆盖 ADC0 sampling、ePWM1
  compare、Timer0 periodic interrupt 和 GPIO status output，RAM/JTAG PASS。

## What "not yet working"

- 任意 Rust 代码（if/while/match, 泛型, 复杂算术）直接编译 — 需要
  LLVM 后端（PATH B）真正落地
- Floating point, 64-bit integers, threads
- UART/SPI/I2C 外设（HAL 层尚无安全封装）
