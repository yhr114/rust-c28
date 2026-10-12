# 工程优化清单与执行顺序

> 更新日期：2026-09-27
> 本文档基于 `f28035-rust-bridge` 合并后的实际核查，列出值得优化的点，
> 按 **成本低→收益高、依赖前置→依赖后置** 排序。

## 优先级总览

| 阶段 | 主题 | 状态 |
|---|---|---|
| **P0** | 工程卫生 | ✅ 已完成 |
| **P1** | 自动化与可信度 | ✅ 大部分完成 |
| **P2** | Safe HAL 纵向样板 | ✅ 已完成 |
| **P3** | case 状态推进 | ✅ 146/146 全部处理 |
| **P4** | 代码组织（按外设拆模块） | ✅ 本轮完成 |
| **P5** | 脚本合并（329→2） | 待做 |

---

## 当前执行状态快照

### case 覆盖（146/146）

| 状态 | 数量 | 说明 |
|---|---|---|
| verified-via-mir | 136 | 上板 RAM/JTAG 验证通过，called=1 |
| compiled-only | 10 | 代码完整可编译，不上板（硬件风险高） |
| 未处理 | 0 | — |

### 外设覆盖

| 外设 | verified | compiled-only | 小计 |
|---|---|---|---|
| GPIO | 12 | 0 | 12 |
| EPWM | 10 | 1 | 11 |
| ADC | 11 | 0 | 11 |
| SPI | 10 | 0 | 10 |
| I2C | 10 | 0 | 10 |
| SCI | 10 | 0 | 10 |
| LIN | 10 | 0 | 10 |
| ECAP | 10 | 0 | 10 |
| EQEP | 10 | 0 | 10 |
| CAN | 9 | 0 | 9 |
| HRCAP | 10 | 0 | 10 |
| PIE | 10 | 0 | 10 |
| WDG | 6 | 4 | 10 |
| SYS | 5 | 5 | 10 |
| Timer/JTAG/Integration | 3 | 0 | 3 |

### 代码组织（P4 完成）

`crates/rust-api/src/application.rs` 原 1225 行单文件已拆为：

```
src/application/
├── mod.rs          # 公共 prelude + pub mod xxx + pub use xxx::*
├── gpio.rs         # 16 个 GPIO 函数
├── epwm.rs         # 12 个 EPWM 函数
├── adc.rs          # 11 个 ADC 函数
├── spi.rs          # 10 个
├── i2c.rs          # 10 个
├── sci.rs          # 10 个
├── lin.rs          # 10 个
├── ecap.rs         # 10 个
├── eqep.rs         # 10 个
├── can.rs          # 9 个
├── hrcap.rs        # 10 个
├── pie.rs          # 10 个
├── watchdog.rs     # 9 个
├── sys.rs          # 12 个
├── timer.rs        # 2 个
└── integration.rs  # 2 个（rust_main, rust_et_jtag_setup）
```

拆分后：
- 宿主侧 40 个 host test 全部通过
- `verify-mir-spi_triwire.ps1` 上板 PASS（called=1）
- 原文件备份在 `application.rs.bak`

### C bridge 规模

- `sdk/c-abi/f28035_bridge.c`：4324 行，141 个 void 函数
- 后端 `backend/c28x-mir/src/main.rs`：116 个 classify 条目

---

## 剩余可优化项

### P5：脚本合并（329 → 2）

**现状**：tools/ 下 329 个 ps1，每个 case 一个 build-mir-xxx.ps1 + verify-mir-xxx.ps1，内容 95% 重复。

**目标**：
```powershell
# 通用 build
.\tools\build-mir.ps1 -Case spi_triwire -RustFn rust_spi_triwire_setup

# 通用 verify
.\tools\verify-mir.ps1 -Case spi_triwire
```

**收益**：
- 改 bug 只改一处
- 新 case 不用复制模板
- 老脚本里漏加 `-OnlyExport` 的问题（如 spi_triwire）不会再发生

### P6：harness 合并（152 → 1）

**现状**：每个 case 一个 `platform/firmware/xxx_test.c`，内容都是调 rust_xxx() + called=1 + 死循环。

**目标**：后端 codegen 直接生成 main，或用通用 harness + `-D` 传函数名。

### P7：self-check 全量覆盖

**现状**：`tools/self-check.ps1` 还是空壳，没把 136 个 verified case 加进去。

**目标**：自动扫描 `verify-mir-*.ps1`，批量跑，输出 PASS/FAIL 汇总表。

### P8：C bridge 按外设拆

`f28035_bridge.c` 4324 行，类似 P4 的做法按外设拆成多个 .c 文件。

---

## 上板验证路线（已稳定）

```
Rust 镜像 (crates/rust-api/src/application/*.rs)
    ↓ rustc -Zmir-opt-level=4 -OnlyExport rust_xxx
MIR dump (backend/c28x-mir)
    ↓ classify_mir_function 短路
    ↓ codegen → .asm
TI CGT cl2000
    ↓ assemble + link (RAM cmd)
.out 固件
    ↓ dss + XDS100v1 JTAG 加载
读 called == 1 → PASS
```

关键约束：
- 必须传 `-OnlyExport`，否则后端生成所有函数汇编导致 .text 爆 SARAM
- VoidCall codegen 不调 `emit_f28035_board_init`（之前 .text 从 7K 涨到 8.5K 超 RAM）
- f28035_timer0_isr 里不调 rust_timer0_interrupt()（OnlyExport 没导出会 undefined）
- WDG/SYS 改 PLL/进 idle/复位类 case 只编译不上板