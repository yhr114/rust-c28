# F28035 Rust 安全化开发与 AI 接手指南

更新日期：2026-09-21

这份文件是本工程的开发入口，也是后续 AI 接手时必须先读的说明。目标不是把
TI 的 C 文件机械翻译一遍，而是逐步形成下面这条可审计边界：

```text
业务与控制逻辑（Safe Rust，无 unsafe/extern C）
                  |
类型安全 HAL（Safe Rust API）
                  |
集中且有安全说明的 Rust FFI/PAC
                  |
窄 C ABI + TI 启动、中断和寄存器支持
                  |
               F28035
```

允许保留底层 C。安全目标是让产品业务代码不能绕过 HAL 随意访问寄存器，并把
必须信任的 C/unsafe 范围缩小、测试和审计，而不是为了“100% Rust”删除所有 C。

## 1. 接手前必须确认的事实

先运行：

```powershell
cd C:\Users\61987\Desktop\28035\f28035-rust-bridge
.\tools\report-status.ps1

cd .\sdk\f28035-safe-hal
cargo test
cargo check --features embedded-hal
```

再阅读：

- `../README.md`
- `SAFETY.md`
- `ABI_FREEZE.md`
- `C28X_RUST_ABI.md`
- `migration_ledger.md`
- 要修改的 `app/hardware-tests/<module>/<case>/case.toml` 和 `src/main.rs`
- 对应原始 C case：`..\..\fpga_delivery_28035\case_src\<module>\<case>`

状态的唯一事实来源是每个 case 的 `case.toml`。`report-status.ps1` 从这些文件实时
汇总；`all_cases_status.csv` 只是通过 `tools/export-status.ps1` 生成的快照；迁移
台账中的表格是历史说明，不得用旧数字覆盖 manifest。

## 2. 当前状态快照

截至 2026-09-23，共 146 个 case：

| 状态 | 数量 | 含义 |
|---|---:|---|
| verified | 29 | 已构建并在 F28035 上通过 JTAG 判定 |
| compiled | 54 | 已生成并链接 `.out`，尚未得到板上 PASS |
| scaffold | 63 | 仍是骨架或未完成真实断言 |
| translated | 0 | 当前没有停留在此状态的 case |

模块分布：

| 模块 | 总数 | scaffold | compiled | verified |
|---|---:|---:|---:|---:|
| adc | 10 | 5 | 0 | 5 |
| can | 9 | 7 | 0 | 2 |
| ecap | 10 | 0 | 10 | 0 |
| epwm | 10 | 0 | 1 | 9 |
| eqep | 10 | 10 | 0 | 0 |
| gpio | 12 | 0 | 5 | 7 |
| hrcap | 10 | 10 | 0 | 0 |
| i2c | 10 | 0 | 10 | 0 |
| jtag | 1 | 1 | 0 | 0 |
| lin | 10 | 0 | 10 | 0 |
| pie | 10 | 10 | 0 | 0 |
| sci | 10 | 0 | 10 | 0 |
| spi | 10 | 0 | 10 | 0 |
| sys_clk | 10 | 10 | 0 | 0 |
| wdg_sys | 10 | 10 | 0 | 0 |

已确认的证据：

- HAL 主机单元测试：40 通过，0 失败。
- XDS100v1 配置：`targetConfigs/TMS320F28035_XDS100v1.ccxml`。
- 构建、烧录和 JTAG 状态读取链路可用。

但不能据此声称“整个固件已经具备 Rust 内存安全”：

- 大多数硬件 case 仍直接含有 `extern "C"`/`unsafe`。
- 当前 `build-case.ps1` 用 `rust-to-ti-c` 解析受限 Rust 语法并生成 C，再交给
  TI C 编译器；这不是普通 `rustc` 对目标程序的完整编译。
- 7 个 GPIO case 已正式登记为 Safe HAL 桥接样板：`gpio_output_basic`、
  `gpio_output_readback_basic`、`gpio_toggle_basic`、
  `gpio_direction_switch_basic`、`gpio2_3_low`、`gpio30_low`、
  `gpio_mux_basic`。这些 app case 源码只写 Safe HAL 业务入口，验证命令走
  `tools/verify-safe-hal-case-ram.ps1 -Case <case>`，底层通过 `crates/rust-api`
  + `backend/c28x-mir` 完成 RAM/JTAG PASS。其他硬件 case
  仍主要是直接 FFI/受限 Rust-to-C 路线。
- `integration/safe_hal_control_loop` 已正式登记为非 GPIO 单项的 Safe HAL
  集成样板，覆盖 ADC0 sample、ePWM1 CMPA、Timer0 periodic interrupt 和
  GPIO31 status output，RAM/JTAG PASS。
- `adc/adc_sample_basic`、`epwm/epwm_cmp_basic`、
  `timer/timer0_periodic_basic` 已拆成独立 Safe HAL bridge case，并完成
  RAM/JTAG PASS。
- `embedded-hal` feature 已通过 `cargo check`：`OutputPin`/`StatefulOutputPin`/`InputPin`
  和 `pwm::SetDutyCycle` 已有真实实现（输出锁存回读、CMPA 读写），但 HAL 本身尚未
  链接进任何硬件 case 的 `.out`，端到端硬件行为未在板上验证。

所以当前阶段应准确描述为：测试迁移和上板闭环已建立；Safe HAL 原型已存在；
编译器研究路径已经跑通若干 Safe HAL 上板样板；应用开发路径已有 7 个正式
GPIO 桥接样板、3 个 ADC/ePWM/Timer 单项桥接样板和 1 个集成桥接样板；但绝大多数 case
尚未迁移，产品级内存安全论证尚未完成。

## 3. 从哪里改起

第一优先级是做一个真实的纵向样板，选择一个已验证过的纯内部 GPIO case：

1. 目标 case 的业务入口只调用 `f28035-safe-hal`，不出现 `unsafe`、裸指针或
   自己声明的 `extern "C"`。
2. 目标引脚必须通过拥有权明确的 pin 句柄配置，例如 `pins.gpioN.into_output()`
   后调用 `set_low()`；不能让同一引脚在安全代码中被重复取得。
3. 应用逻辑必须经 `rustc` 和本项目的 C28x 后端/受控代码生成链编译。若现有
   后端还不支持 HAL 所需的结构体、泛型或调用约定，应先扩展并测试后端；不得
   仅在语法转换器中把一段 Rust 文本替换成等价 C 后宣称获得 Rust 内存安全。
4. 底层可继续调用窄 C ABI，但 FFI 只能存在于 HAL/PAC 内部，并为每个 unsafe
   写明调用前提、资源所有权、并发条件和返回值约束。
5. 完成主机测试、目标构建、XDS100v1 烧录和 JTAG PASS 后，把这条路径固化为
   后续 GPIO、ADC、PWM 和通信外设的模板。

在这条纵向样板完成前，继续批量把 scaffold 变成“直接 FFI 的 compiled”只能
增加功能覆盖，不能明显提升 Rust 安全覆盖率。

## 4. 分阶段路线

### P0：保证记录可信（当前基本完成）

- `case.toml` 是状态事实源。
- `tools/report-status.ps1` 负责实时统计。
- `tools/export-status.ps1` 负责刷新 CSV 快照。
- 只有实际看到 `F28035_RUST_CASE=PASS` 才能标记 `verified`。

完成标准：统计数量一致；每个 verified 都有 `verification` 证据；失败和外部接线
依赖有记录。

### P1：接通 Safe HAL 与目标构建（下一步）

- 先选一个纯内部 GPIO case 做纵向样板，再迁移其他纯内部 GPIO case。
- 应用层不得直接访问 `pac::ffi`。
- 明确使用真实 Rust 目标代码生成，记录 `.rlib`/`.obj`/`.out` 的来源与链接图。
- 为 Rust/C ABI 增加参数宽度和返回值测试。

完成标准：至少一个上板 PASS 的 case 同时满足“应用层零 unsafe/零 extern C”和
“目标代码来自 rustc 路径”。

### P2：补强 HAL 安全模型

- 把 GPIO 改为一次 `split/take` 后得到独占 pin token，防止重复持有同一引脚。
- 禁止公开构造重复 ADC/Timer/PWM 句柄；审查 `AdcResults::new()` 等入口。
- 将初始化失败和非法动态参数改成明确的 `Result<_, Error>`；编译期可判定的非法
  常量尽量在编译期拒绝。
- 定义临界区和中断共享规则，审计主循环/ISR 的别名、`static mut` 和原子性。
- 修复 `embedded-hal` feature；先实现真实语义，再声明对应 trait。
- 补齐 GPIO 输出锁存回读、PWM compare 回读、enable/disable、Timer start 等占位项。

完成标准：`cargo test` 与所有启用 feature 的 `cargo check` 均通过；安全 API 无法
构造重复资源或明显非法状态；unsafe 清单有逐项说明。

### P3：按产品需求扩展外设

推荐顺序：GPIO -> 时钟/看门狗/PIE -> ADC/Timer/ePWM -> SCI/SPI/I2C/CAN ->
eCAP/eQEP/HRCap/LIN。只实现产品和测试真正需要的能力，不机械复制 TI 全部 API。

每个外设都按同一顺序完成：窄 C ABI（若确有需要） -> FFI -> safe HAL -> 主机测试
-> 单个硬件 case -> 异常/边界 case -> 文档与状态。

完成标准：应用层只看见 safe HAL；正常、超时、错误标志和恢复路径均有测试。

### P4：建立可复核的安全证据

- 主机测试：寄存器映射、状态机、边界值、错误传播和纯算法。
- 编译检查：默认 feature 和所有正式 feature 均构建；禁止应用层 unsafe/FFI。
- 后续优化：引入 `compile_fail`/`trybuild` 负向测试，专门记录“C 能编译但
  Safe Rust HAL 应拒绝”的误用样例，例如输入脚调用输出方法、重复取得同一外设、
  非法 GPIO/XINT 常量和绕过安全构造器的 PWM/Timer 配置。该项用于补强安全证据，
  但不阻塞当前优先级；近期仍先实现 Safe Rust HAL 覆盖和 RAM/JTAG 上板闭环。
- ABI 检查：C28x 的 16 位 `char`、`u16/u32` 布局、符号和调用约定。
- 硬件测试：内部回环、外部接线、复位、超时和中断竞争分别标注。
- 代码审计：所有 C、unsafe、链接脚本、启动代码、ISR 包装和自定义后端。

完成标准：可以明确回答“哪些缺陷由编译器排除、哪些由 HAL 约束、哪些由测试
发现、哪些仍属于可信底座”，而不是只用 case PASS 数量代表安全性。

## 5. 每次修改的固定工作流

1. 选择一个最小 case，读取原 C、Rust case、manifest、相关 C ABI 和 HAL。
2. 写下该 case 的资源、前置条件、外部接线、超时和失败码。
3. 先补 HAL 主机测试，再实现最小必要接口；不要把整段业务流程塞进 C bridge。
4. 应用层不新增 `unsafe`、`extern C`、裸寄存器地址或直接 `pac::ffi` 调用。
5. 运行 `cargo test`；涉及 feature 时运行对应 `cargo check --features ...`。
6. 构建：`.\tools\build-case.ps1 -Case <module>/<case>`。
7. 上板：

```powershell
.\tools\flash-and-verify-case.ps1 `
  -Case <module>/<case> `
  -SkipBuild `
  -TargetConfig .\targetConfigs\TMS320F28035_XDS100v1.ccxml
```

8. 按证据更新 `case.toml`，运行 `report-status.ps1` 和 `export-status.ps1`。
9. 更新本文“当前状态快照”、`migration_ledger.md` 的相关失败记录，并写清
   测试日期、探针、接线、状态和 fail code。

## 6. 状态更新规则

- `scaffold`：只有骨架、空循环、假 PASS 或关键断言未实现。
- `translated`：逻辑已迁移，但目标构建还未成功。
- `compiled`：已生成并链接 `.out`，但没有板上 PASS；外部激励缺失也保持此状态。
- `verified`：指定硬件、接线和探针下取得 `status=1 && fail_code=0`。

禁止事项：

- 不因“编译成功”写 `verified`。
- 不因主机单元测试通过声称物理寄存器或引脚正确。
- 不用示波器看到低电平替代固件中的失败码和 JTAG 验证；两者应互相补充。
- 不把 C 中的循环和整套业务逻辑全部下沉到一个 C 函数后称为 Safe Rust 迁移。
- 不修改无关用户文件，不覆盖现有实验记录。

## 7. 当前明确缺口

- 最大缺口：Safe HAL 已进入应用开发路径的 7 个 GPIO 桥接 case、3 个
  ADC/ePWM/Timer 单项 case 和 1 个控制环集成 case，但还没有覆盖 GPIO
  input/loopback、通信、捕获、编码器、PIE、时钟和看门狗等主要业务 case。
- 通信时序型 case（SPI/SCI/I2C/LIN，约 40 个）当前仍是 C bridge 兜底：
  app 侧 `*_setup()` 走 `c28x-mir` 的 `MirOperation::VoidCall`，生成
  `LCR f28035_<module>_<case>`，收发时序/轮询/失败码全在 C。已做的纵向
  样板是 `pac.rs::spi::run_internal_loopback`（SPI internal-loopback 的 Rust
  时序，6 个 host 测试 1:1 断言失败码，`cargo test --test-threads=1` 全绿）；
  它未经 C28x 后端降低、未上板，target 仍保留 C 兜底。推广到其余通信 case
  前需先给后端补"有界轮询 + 读回 + 多分支失败码"的通用通信 codegen。
- 63 个 scaffold：ADC 5、CAN 7、eQEP 10、HRCap 10、JTAG 1、PIE 10、
  SYS_CLK 10、WDG_SYS 10。
- 55 个 compiled 仍需按测试条件上板验证，其中部分依赖跳线或外部激励。
- HAL 仅覆盖 GPIO、部分 ADC、Timer0、ePWM1；通信、捕获、编码器、PIE、时钟和
  看门狗没有形成完整的 safe API。
- `embedded-hal` trait 已在 HAL 中实现并通过 `cargo check`，但 HAL 未进入硬件 case
  的目标构建，不能对外宣称端到端兼容。
- 当前 GPIO token、ADC 构造和中断访问仍需更严格的唯一所有权/并发设计。
- C ABI、TI 库、自定义代码生成、链接脚本和 ISR 仍属于待持续审计的可信底座。
- 尚无自动化门禁阻止应用层新增 `unsafe`/`extern C`，也没有全 feature CI。

## 8. 交付汇报模板

后续 AI 完成一项工作时，最终汇报至少包含：

```text
完成：修改了哪些 HAL/FFI/case，解决了什么风险。
证据：cargo test/check 结果；目标构建结果；JTAG status/fail_code；必要的接线说明。
状态：哪些 case 从什么状态变成什么状态，新的总计是多少。
边界：仍保留哪些 C/unsafe，为什么目前可以接受。
下一步：一个最小且可验证的后续任务。
```

任何“更安全”的结论都必须对应具体机制和证据，例如所有权阻止重复占用、类型
阻止非法状态、边界检查阻止越界、临界区避免竞争；不能仅以“使用了 Rust”作为结论。
