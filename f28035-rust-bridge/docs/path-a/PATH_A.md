# 路径 A：应用、Safe HAL 与 MIR

更新日期：2026-10-19。本文汇集原应用/PATH A 的安全边界、迁移台账、硬件恢复和实验记录；开发约定与 AI 接手指南已于 2026-10-20 迁出为 [F28035_RUST_DEV_GUIDE.md](F28035_RUST_DEV_GUIDE.md)。原文内容保留在对应章节，章节头标明来源和校验值。原文里提到的旧文档文件名请按下方目录定位。各 `case.toml` 仍是用例状态的事实来源；本文中的历史统计不应代替实时汇总。

> 本文是 PATH A 的独立文档集：只覆盖应用、Safe HAL 与 MIR，不涉及 LLVM 后端与
> B-1 工具链。本目录内的文档不引用、不依赖其他路线文档。

> 新开发任务的默认路线以[项目 README](../../README.md)为入口选择。
> 本文中的 Rust-to-C / MIR 命令用于现有对应流程，不代表项目默认主路径，
> 也不因主路径调整而自动迁移已有用例。

> 开发约定与 AI 接手指南（原 a-1 章节）已于 2026-10-20 迁出为独立文档
> [F28035_RUST_DEV_GUIDE.md](F28035_RUST_DEV_GUIDE.md)；它承载开发流程、
> 状态规则、明确缺口和 GPIO PAC 直编样板记录，不是路线文档。本文只保留
> 安全边界、迁移台账、硬件恢复和实验记录。修改该指南不替代更新本文，
> 仍按根目录 [AGENTS.md](../../AGENTS.md) 两份路线文档与工作日志同步。

## 维护记录

每次工程修改都按根目录 [AGENTS.md](../../AGENTS.md) 更新相关路线说明，并在
[WORK_LOG.md](../../WORK_LOG.md) 记录修改、过程事件、验证结果和遗留事项。

| 日期 | 主题 | 结论 |
|---|---|---|
| 2026-10-21 | B-2 活动入口迁出 | 删除 PATH A 中已失效的 B-2 优化入口表述，编译器工作统一由 B-1 维护；应用、Safe HAL、MIR 用例和验证等级均未改变。联合 oracle 的 6 个 LLVM 用例通过，MIR control-loop 因当前 nightly rustc_driver API 漂移构建失败，未改写历史 golden |
| 2026-10-20 | 默认路线入口同步 | 新任务由项目 README 选择主路径；本目录保留应用安全约定及既有 Rust-to-C / MIR 流程，不复制编译器侧状态，不改变用例验证等级 |
| 2026-10-20 | a-1 章节迁出 | 开发与 AI 接手指南整节迁至 [F28035_RUST_DEV_GUIDE.md](F28035_RUST_DEV_GUIDE.md)（正文未改动）；本文目录移除第 1 项并重新编号为 1–9，锚点 `a-2`..`a-10` 保持不变，`#a-1` 无外部引用故不产生断链 |
| 2026-10-19 | 文档合并与维护规则 | A 路线资料合为本文；此后每次修改都更新本文相关内容及工作日志 |
| 2026-10-19 | P5/P7 状态同步 | build-mir/verify-mir/self-check/retire 脚本已落地，静态校验通过（DryRun 142/142）；P5 由「待做」改为「已实现，待真机验证」，P7 由「空壳」改为已实现 |
| 2026-10-20 | GPIO PAC 常用操作 | Safe HAL 的 B-1 `direct-obj-mmio` 路径通过 PAC 执行输出、输入配置、数据读回和 MUX；宿主 53 项与文档测试 15 项通过，GPIO0/GPIO34 RAM/JTAG 通过；应用 case 的 C bridge 路径仍保留 |
| 2026-10-20 | PATH A 文档独立成目录 | 本文与 [F28035_RUST_DEV_GUIDE.md](F28035_RUST_DEV_GUIDE.md) 一并迁入 `docs/path-a/`；目录内文档不再引用编译器路线文档（删除 3 处跨路线链接与指南中的 B-2 状态小节），相对链接按新层级改为 `../../`；README / AGENTS / SETUP / WORK_LOG 入口同步指向新路径 |
| 2026-10-20 | 接收编译器路线的架构段 | 从编译器路线文档的 Architecture 章节迁入 Track 1（应用路径）与 PATH 2A（PAC 层、MIR 分类器、五种 MMIO lowering、XAR 间接寻址、EALLOW 自动包裹）及 MIR 硬件验证记录，作为第 10 节（`a-11`）；目录增补第 10 项；迁入段内原有的 `#b-1` 链接改为文字说明，本目录保持零跨路线锚点 |

## 目录

1. [Safety Contract](#a-2)
2. [临界区与中断共享规则](#a-3)
3. [Unsafe 审计清单](#a-4)
4. [迁移台账：C case → Rust（F28035）](#a-5)
5. [工程优化清单与执行顺序](#a-6)
6. [F28035 Flash / CSM Status](#a-7)
7. [Zero-C RAM GPIO experiment](#a-8)
8. [One-file Rust application pilot](#a-9)
9. [C28x Rust ownership method RAM pilot](#a-10)
10. [架构：应用路径与 MIR 后端](#a-11)

> 开发与 AI 接手指南（原 a-1 章节）见 [F28035_RUST_DEV_GUIDE.md](F28035_RUST_DEV_GUIDE.md)。

---

<a id="a-2"></a>

## Safety Contract

> 原文：`f28035-rust-bridge/docs/SAFETY.md`；SHA-256：`7b952b68967a3c24ee6df511ecbaa64f8a821371e9b341558719e2b2010205c7`。

### 可以称为 Safe Rust 的部分

- `app/hardware-tests/*/*/src/main.rs` 目前仍直接 `extern "C"` 调 f28035_* C bridge；
  P1 目标是让应用层只经 `f28035-safe-hal` 访问寄存器，case 内不出现裸 `unsafe`/FFI。
- 外设从 `Peripherals::take()` 单次取得，防止普通流程重复持有。GPIO、XINT、
  Timer、ePWM、ADC 和总线控制器的硬件资源句柄均为私有构造器，且不能安全地复制或克隆。
- GPIO、定时器周期和 PWM 周期使用类型或 const 泛型表达。
- C 返回值在构造安全句柄前进行验证。
- 所有 FFI 调用都收敛在 Rust HAL/PAC 边界内。

### 可信底座

以下部分仍需要人工审计，Rust 编译器不能证明其安全：

- `sdk/c-abi/f28035_bridge.c` 中的 TI 寄存器操作。
- C28x 启动代码、链接脚本和 TI 运行库。
- C ISR 的保存现场、恢复现场和中断返回。
- Rust/C 参数与返回值的实际寄存器布局。
- 主循环和中断共享状态时的原子性与临界区。
- 自定义 MIR 到 C28x 汇编后端的代码生成正确性。

因此，准确描述是：业务层为 Safe Rust，整个固件是“Safe Rust + 经审计的
unsafe/C 可信底座”，不是纯 Rust 全栈内存安全。

### C ABI 允许项

优先使用：

- 无参数、无返回值函数。
- `u16`/C 侧明确的 16 位无符号类型。
- 已单独验证过的 `u32`/`i16`/`i32`。
- 用整数句柄或索引表达硬件资源。
- 用 `0/1` 的 `u16` 表达布尔值。

未经单独 ABI 测试，不要跨边界传递：

- C `char` 与 Rust `u8`。
- Rust `bool`、引用、切片、字符串和 trait object。
- 结构体、联合体、枚举或数组的按值参数。
- 函数指针和任意裸指针。

C28x 是 16 位字寻址架构，TI C 的 `char` 为 16 位，而 Rust `u8` 必须是
8 位。字节指针和缓冲区必须使用项目 ABI 文档规定的逻辑字节地址模型。

### 新增接口检查表

- C 头文件使用固定、已验证宽度的别名。
- C 实现在访问寄存器前检查编号、范围和模式。
- Rust FFI 声明与 C 的参数顺序、宽度、返回值完全一致。
- `unsafe` 只出现在封装内部，并有可检查的安全前提。
- 安全 API 不允许构造非法引脚、通道或周期。
- 明确函数能否在中断上下文调用。
- 明确寄存器或全局状态是否会被主循环和中断同时修改。
- 添加主机测试、ABI 汇编检查和上板测试。

### 当前已知限制

- `embedded-hal` trait 实现已调用真实 HAL 方法（输出锁存回读、CMPA 读写、Timer
  状态类型）。零 C RAM GPIO34 样板已有 Safe HAL 入口并通过 JTAG，但后端仍按固定
  MIR 模式生成等效寄存器指令；目标端尚未执行 `take`/`claim` 的真实状态机。
- `assert!` 最终行为依赖目标端 panic 实现；正式产品建议把可恢复配置错误
  改成 `Result`，把编译期常量错误尽可能变成编译期拒绝。
- 自定义 MIR 后端只支持已经实现和验证的 Rust 子集。
- 外设单例标志本身不是通用并发原语，应在启用中断前完成 `take()`。

---

<a id="a-3"></a>

## 临界区与中断共享规则

> 原文：`f28035-rust-bridge/docs/CONCURRENCY.md`；SHA-256：`6f61b6e9145e341828da55f55b5f797a3a032be3885b7ef72c7de4e09e2754f5`。

> 定义于 2026-09-21。C28x 是单核，无 cache 一致性问题；风险集中在
> 主循环与 ISR 对**同一寄存器/全局变量**的并发读写。

### 1. 资源所有权与 ISR 的边界

- **配置类**寄存器（ePWM 周期/比较、Timer 周期、GPIO 方向/引脚 mux、ADC SOC 配置、
  时钟/PLL）只在**主循环上下文、且中断尚未使能**的阶段写入。HAL 的类型状态
  （`StoppedTimer0`/`PeriodicTimer0`、`Pwm1` -> `Pwm1Output`）在编译期禁止
  在"运行中"状态下改周期。
- **ISR 上下文**只允许调用标注为 ISR-safe 的窄接口：
  - `f28035_timer0_ack()`（PIEACK，写-only 命令寄存器）
  - 清除状态标志（ADC INTFLGCLR、`set_compare` 影子装载前的 CMPA 直写）
  - 原子回读一个对齐的 u16 状态（`interrupt_count`）
- 任何"读-改-写"（`modify`）序列**不得跨主循环与 ISR 共享同一寄存器**；
  若必须，先定义临界区（第 2 节）再操作。

### 2. 临界区（C28x 无硬件互斥，用 DINT/EINT）

- 共享可变状态（主循环与 ISR 都写/读的全局变量）必须用 `DINT`/`EINT`
  短临界区包裹，且临界区**必须嵌套感知**：
  ```text
  DINT;  ... 最短必要操作 ...; EINT;
  ```
  长计算、循环、阻塞禁止放在临界区内。
- 命令类写-only 寄存器（GPIO SET/CLEAR/TOGGLE、PIEACK、ADCSOCFRC1、
  ADCINTFLGCLR）**不是**读-改-写，本身原子，**不需要**临界区。
- 配置类寄存器的 RMW（`TiWordAddress::modify`）若在 ISR 使能后仍被主循环
  调用，必须用临界区；否则该寄存器的写入只能在 ISR 关断期完成。

### 3. 中断共享状态的可变全局

- **禁止** `static mut`（HAL 已清零；`cargo test` 依赖的 host 原子变量
  是 `#[cfg(test)]` 例外，不上 target）。
- 主循环与 ISR 共享的可变计数器/标志，若将来需要，使用
  `core::sync::atomic` 的 `AtomicU16`（C28x 上对齐 u16 原子读/写），
  并在 `UNSAFE_AUDIT.md` 记录其访问上下文。当前 HAL 尚未暴露此类共享量。

### 4. ISR 包装约定

- 中断序言/尾声归运行时：`crates/c28x-rt/interrupts.s` 的 `ISR_ENTER`/
  `ISR_EXIT` 宏负责保存/恢复现场（`XT`、`XAR4..XAR7`、`AR1H:AR0H`，并为
  handler 清 `OVM`/`PAGE0`/`AMODE`）与 `IRET` 返回；该序列与 cl2000 对
  `__interrupt` 的输出逐条等价（opcode 已对照）。**不再**依赖 TI C 的
  `__interrupt` 函数，也不再是 `RTI`（C28x 是 `IRET`）。
- 该 trampoline 只做硬件收尾：清 CPU 定时器 `TIF`（读改写）与 `PIE_ACK`；
  它**不碰** `IER`/`EINT` —— CPU 级使能由 `main` 在启动阶段完成。
- Rust 侧 `rust_timer0_interrupt` 只做业务（ack + 业务逻辑），仍是 ISR-safe
  窄接口。
- Rust ISR 体**不得**：分配内存、调用可能阻塞的 IO、写日志、超过一个
  共享寄存器的 RMW。
- 每个 ISR 包装的寄存器副作用必须在 `UNSAFE_AUDIT.md` 的 FFI 表中标注
  "可在 ISR 上下文调用 = 是/否"。

### 5. 审计检查点

| 检查项 | 现状 |
|---|---|
| HAL 是否含 `static mut` | 否（已清零，改 `AtomicU16`） |
| 配置类 RMW 是否被限定在 ISR 关断期 | 是（类型状态机 + 本文约定） |
| 命令类写寄存器是否被识别为原子 | 是（见第 2 节白名单） |
| ISR-safe 的 FFI 子集是否有清单 | 待补（`UNSAFE_AUDIT.md` 表 4 列"ISR-safe"） |
| 共享可变全局是否走原子 | 是（`AtomicU16` 约定，第 3 节） |

---

<a id="a-4"></a>

## Unsafe 审计清单

> 原文：`f28035-rust-bridge/docs/UNSAFE_AUDIT.md`；SHA-256：`cd7845714ff6efd27ebb03c676fe757acf15ee2ca801e1c94811434b1b47cc9d`。

> 生成日期：2026-09-21。任何新增/修改 `unsafe` 后须同步更新本文。

### 统计

| 文件 | `unsafe` 块 | `pub unsafe fn` | 说明 |
|---|---:|---:|---|
| `sdk/f28035-safe-hal/src/lib.rs` | 24 | 0 | 全部在安全 API 内部调用 C bridge |
| `sdk/f28035-safe-hal/src/pac.rs` | 67 | 70 | FFI 层：target 路径 + host stubs |
| **合计** | **91** | **70** | |

### 逐项说明

#### lib.rs（安全 API 层，调用 C bridge）

所有 `unsafe` 块均遵循同一模式：
1. 在 unsafe 之前，const-generic 参数已通过 `assert!` 或编译器推导检查合法性；
2. 调用的 FFI 函数来自 `pac::ffi`，签名与 C bridge 一一对应；
3. 返回值立即检查（`if configured == 0 { release; return Err }`），失败时归还资源；
4. 块内无指针运算、无 `static mut`、无 `mem::transmute`。

| # | 行 | 调用 | 调用前提 | 资源所有权 | 并发条件 | 返回值约束 |
|---:|---:|---|---|---|---|---|
| 1 | `system_init` | `ffi::f28035_system_init()` | 启动路径，仅调一次 | 无（全局初始化） | ISR 未使能 | 无返回值 |
| 2 | `Peripherals::take` | `ffi::f28035_take_peripherals()` | 启动路径 | 独占所有权根 | ISR 未使能 | `1`=可用，`0`=已被取 |
| 3 | `Gpio::output` | `ffi::f28035_gpio_make_output(PIN)` | `PIN ≤ 44`（assert）；pin 未 claimed | 取得后 pin 被 mask 标记 | 主循环上下文 | `1`=成功，`0`=拒绝 |
| 4 | `Gpio::input_with` | `ffi::f28035_gpio_make_input(PIN,…)` | `PIN ≤ 44`，`QUAL ≤ 3`（assert） | 同上 | 主循环 | `1`/`0` |
| 5 | `Gpio::xint` | `ffi::f28035_gpio_configure_xint(LINE,PIN,EDGE)` | `LINE∈{1,2}`，`PIN ≤ 31`，`EDGE∈{0,1,3}` | pin 被 claimed | 主循环 | `1`/`0` |
| 6 | `OutputPin::set` | `ffi::f28035_gpio_write(PIN,high)` | 仅已 claimed 的 pin 句柄可构造 | 独占 | 主循环 | 无 |
| 7 | `OutputPin::toggle` | `ffi::f28035_gpio_toggle(PIN)` | 同上 | 独占 | 主循环 | 无 |
| 8 | `OutputPin::is_high` | `ffi::f28035_gpio_read(PIN)` | 同上 | 独占 | 主循环 | `0`/`1` |
| 9 | `InputPin::read` | `ffi::f28035_gpio_read(PIN)` | 已 claimed | 独占 | 主循环 | `0`/`1` |
| 10 | `AdcResults::read` | `ffi::f28035_adc_result(INDEX)` | `INDEX ≤ 15`（assert） | Peripherals 独占 | 主循环 | `u16` 结果 |
| 11 | `AdcResults::sample` | `ffi::f28035_adc_sample(CHANNEL)` | `CHANNEL ≤ 15`（assert） | 独占 | 主循环 | `u16` |
| 12 | `AdcResults::timeout_count` | `ffi::f28035_adc_timeouts()` | 无需参数 | 独占 | 对齐 u16 读 | `u16` |
| 13 | `Timer0::start_once` | `ffi::f28035_timer0_start_once_ms(PERIOD)` | `1 ≤ PERIOD ≤ 1000`（assert） | Timer0 独占 | 主循环 | `1`/`0` |
| 14 | `Timer0::start_periodic` | 同上 | 同上 | 同上 | 主循环 | `1`/`0` |
| 15 | `PeriodicTimer0::interrupt_count` | `ffi::f28035_timer0_interrupts()` | 定时器已启动 | 独占 | 对齐 u16 | `u16` |
| 16 | `PeriodicTimer0::stop` | `ffi::f28035_timer0_stop()` | 独占 | 独占 | 主循环 | 无 |
| 17 | `StoppedTimer0::set_period` | `ffi::f28035_timer0_set_period_ms(NEW)` | `1 ≤ NEW ≤ 1000` | 已停止 | 主循环 | `1`/`0` |
| 18 | `StoppedTimer0::restart` | `ffi::f28035_timer0_restart()` | 已停止 | 独占 | 主循环 | 无 |
| 19 | `Pwm1::configure` | `ffi::f28035_epwm1_configure(PERIOD)` | `PERIOD > 0`（assert） | ePWM1 独占 | 主循环 | `1`/`0` |
| 20 | `Pwm1Output::set_compare` | `ffi::f28035_epwm1_set_compare(ticks)` | 已 configure | 独占 | 主循环 | 无 |
| 21 | `Pwm1Output::get_compare` | `ffi::f28035_epwm1_compare()` | 已 configure | 独占 | 对齐 u16 | `u16` |
| 22 | `Pwm1Output::enable` | `ffi::f28035_epwm1_enable()` | 已 configure | 独占 | 主循环 | 无 |
| 23 | `Pwm1Output::disable` | `ffi::f28035_epwm1_disable()` | 同上 | 独占 | 主循环 | 无 |

#### pac.rs（FFI 层）

`pub unsafe fn` 共 70 个，分两组：

**Target 路径（`#[cfg(not(test))]`）：34 个**
- 每个函数体仅包含固定地址的 MMIO 读写（`C28xMmio` + `TiWordAddress`），不做地址计算；
- 地址常量来自 TI 寄存器头（DSP2803x_*.h），已交叉验证；
- 调用前提由 HAL 层 const-generic assert 保证。

**Host stubs（`#[cfg(test)]`）：36 个**
- 确定性内存模型（`AtomicBool` / `AtomicU16` / `AtomicU64`），无裸指针；
- 用于 `cargo test` 验证 HAL 类型状态机。

### 不含的 unsafe 类别

| 类别 | 状态 |
|---|---|
| `static mut` | **已清零**（原 `HOST_CMPA` 改为 `AtomicU16`） |
| `mem::transmute` | 无 |
| 裸指针运算（`addr + N`） | 无，所有地址为编译期常量 `TiWordAddress` |
| `std::ptr::read/write` | 无 |
| 动态数组/slice 跨 FFI | 无 |

### 修改规则

- 新增 `unsafe` 必须对应上表一行，填写调用前提/资源所有权/并发条件/返回值约束；
- `lib.rs` 中不允许新增 `extern "C"` 声明（FFI 收拢在 `pac::ffi`）；
- 应用层（`app/hardware-tests/*/src/main.rs`）不允许 `unsafe`，仅通过 `f28035-safe-hal` 安全 API 操作外设。

---

<a id="a-5"></a>

## 迁移台账：C case → Rust（F28035）

> 原文：`f28035-rust-bridge/docs/migration_ledger.md`；SHA-256：`76b48864e47bf8494bf0581d701d4314ffad3c5619c6009e75749f3f3bd2fc2a`。

> 目标：把 `fpga_delivery_28035/case_src` 的 C 语言 F28035 测试用例逐个迁移为 Rust，
> 并建立可追踪、可复核的「构建 + 烧录 + 验证」闭环。
>
> 每个 case 的 `case.toml` 是迁移状态的唯一权威记录；`tools/report-status.ps1`
> 从 manifest 实时统计。本台账保留迁移决策、失败原因和历史记录，旧表格不得
> 用来覆盖 manifest。总路线和 AI 接手规则见`AGENTS.md`。

### 1. 数据映射

- 源：`C:\Users\61987\Desktop\28035\fpga_delivery_28035\case_src\<module>\<case>\`
  - `src/main.c`：被测 C 主程序
  - `include/case_config.h`：失败码 / 常量
  - `case.mk`：SDK 构建描述
- 目标：`C:\Users\61987\Desktop\28035\f28035-rust-bridge\app\hardware-tests\<module>\<case>\`
  - `src/main.rs`：Rust 被测主程序（`rust_main()` + 可选 `rust_timer0_interrupt()`）
  - `case.toml`：迁移状态元数据（`status`、`source_c`、`verification`）
- 映射结论：原 C 集合对应 140 个目标 case，所以当前目标总数为 140。

### 2. 闭环命令（可追踪的最小操作单元）

每个 case 的「构建 → 烧录 → 验证」链路固定如下：

```powershell
## 1) 构建（Rust -> 生成C -> cl2000 编译 -> 链接 .out + .map）
.\tools\build-case.ps1 -Case <module>/<case>

## 2) 烧录 + JTAG 验证（依赖 XDS100 连接；-SkipBuild 时直接烧已有 .out）
.\tools\flash-and-verify-case.ps1 -Case <module>/<case> [-SkipBuild]

## 3) 全量进度统计（读各 case.toml 的 status 分组计数）
.\tools\report-status.ps1
```

判定语义（`verify-case.js`）：
- `f28035_test_status=1 && f28035_test_fail_code=0` → **PASS**（→ `verified`）
- `f28035_test_status=2` → **FAIL**（打印对应 EPWM1 寄存器，仍记录失败码）
- `5s` 内未就绪 → **TIMEOUT**（通常死循环 / 复位 / 未通过 pass）
- JTAG 连接异常 → **ERROR**

### 3. 状态机（case.toml.status）

```
scaffold  →  translated  →  compiled  →  verified
   骨架        已按C改写       Rust转换+TI编译+链接通过      硬件JTAG上 PASS
```

- 只有走完「烧录 + JTAG 读 `f28035_test_status`」拿到 PASS，才允许 `compiled → verified`。
- 失败/TIMEOUT 保持 `compiled`，并在本台账「失败记录」登记原因与失败码。

### 4. 翻译器能力约束（决定 Rust 怎么写）

`f28035-rust-bridge/tools/rust-to-ti-c` 的 C 输出路径只接受一个**受限子集**：

- `rust_main()`：`pub extern "C"`、`#[unsafe(no_mangle)]`、**无参数**、**void 返回**。
- 函数体**恰好一个 `unsafe { ... }` 块**，块内仅允许：
  1. `extern "C"` 声明的 FFI 调用，**实参只能是 u16 字面量**；
  2. `let x = <返回u16的FFI>(...);`
  3. 裸 `if x == N { ... }` / `if x != N { ... }`（**无 else 分支**）；
  4. `return;`。
- **不支持** `for` / `while` / 裸循环 / 结构体 / 切片 / 引用 / 字面量之外的参数。

#### 带循环 C case 的迁移策略

源 C 大量使用 `for` 循环扫寄存器 / 引脚。因为 Rust 侧不能写循环，策略是：

> **把循环 / 寄存器扫描逻辑下沉到 C-ABI**：新增一个封装 C 函数（内部完成循环 +
> 断言 + `f28035_test_pass/fail`），Rust 侧只做「调用封装 + 必要的裸 if 断言」。

这样既守住 Rust 翻译器子集约束，又 1:1 复刻 C 行为。封装函数统一命名
`f28035_<module>_<action>(...)`，全部实参用 u16 字面量表达。

### 5. C-ABI 现状与缺口（`sdk/c-abi/f28035_bridge.{h,c}`）

已就绪模块：`gpio`、`adc`、`timer0`、`epwm`、`can`(mux 组合)、测试运行时
（`f28035_test_pass/fail/status/fail_code`、`f28035_delay_us`、`f28035_system_init`）。

未实现（源 C 全为直接寄存器操作，需补 C-ABI）：
`spi`、`i2c`、`lin`、`sci`、`ecap`、`eqep`、`hrcap`、`pie`、`sys_clk`、`wdg`、`jtag`。

### 6. 迁移批次（按模块 + C-ABI 依赖排序）

| 批次 | 模块 | 依赖 | case 数 | 说明 |
|---|---|---|---|---|
| B0 样板 | gpio / epwm | 已就绪 | 2 | 2 个 `compiled`（`gpio_input_basic`、`epwm_tz_external_tz1_ost`）烧录确认 |
| B1 | gpio | 已就绪 | 3 | `gpio_pin_walk_basic` 等，纯迁移不新增 C |
| B2 | spi | 需补 SpiRegs | 10 | |
| B3 | i2c | 需补 I2cA/B | 10 | |
| B4 | lin | 需补 LinA/B | 10 | |
| B5 | sci | 需补 Scia/B | 10 | |
| B6 | ecap | 需补 ECap | 10 | |
| B7 | eqep | 需补 Eqep | 10 | |
| B8 | hrcap | 需补 HRCap | 10 | |
| B9 | pie | 需补 PieRegs | 10 | |
| B10 | sys_clk | 需补 SysCtrl | 10 | |
| B11 | wdg_sys | 需补 WdRegs | 10 | |
| B12 | can(补) | 已就绪 | 7 | can 模块剩余 7 个 scaffold |
| B13 | jtag | 特殊 | 1 | `et_jtag` 非独立 C 程序（JTAG 流程共用镜像），单独评审 |

合计：B0=2，B1..B12 已列 scaffold，B13=1。

### 7. 进度看板

> 2026-09-21 实时状态：`verified 23 / compiled 55 / scaffold 63`，总计 141。
> 以后以 `tools/report-status.ps1` 输出为准。
> 已推进：`epwm_reg_rw_smoke`（scaffold → verified）、B1 gpio 批次 3 个（1 verified + 2 compiled 外部跳线）、M1 spi 批次 10 个（全部 → compiled，构建通过，`SpibRegs` 别名已补入 `F28035_Peripheral_symbols.cmd`）。

（下表随每次推进更新；`✓` = 已 verified，`⚙` = compiled 未确认，`—` = scaffold）

| 批次 | module/case | 依赖 | 当前 | 目标 | 备注 / 失败码 |
|---|---|---|---|---|---|
| B0 | gpio/gpio_input_basic | 就绪 | ⚙ | —（外部接线） | 需 GPIO30↔GPIO0 跳线；板上无接线 → FAIL 0x0402（FAIL_LOW），JTAG 管道正常 |
| B0 | epwm/epwm_tz_external_tz1_ost | 就绪 | ⚙ | —（外部激励） | 需 UVM 拉 GPIO15/TZ1n 低；无激励 → FAIL 0xEE03（OST_NOT_SET），JTAG 管道正常 |
| B1 | epwm/epwm_reg_rw_smoke | 已补 C-ABI | ✓ | ✓ | verified：reset 快照 + 掩码 16-bit RW；HR 电源/配置寄存器板上不可写已裁剪，见 §9 |
| B1 | gpio/gpio_pin_walk_basic | 已补 C-ABI | ✓ | ✓ | **verified**：A(0..31)+B(32..44) 逐脚驱动 + mux/qsel 扫描 + 复位回读；循环下沉 C-ABI，纯内部自检 PASS |
| B1 | gpio/gpio_xint_falling_basic | 已补 C-ABI | ⚙ | —（外部接线） | XINT1 下降沿；需 30↔0 跳线 → FAIL 0x0901（源 C FAIL_IRQ），保持 compiled |
| B1 | gpio/gpio_xint_rising_basic | 已补 C-ABI | ⚙ | —（外部接线） | XINT1 上升沿；需 30↔0 跳线 → FAIL 0x0801（源 C FAIL_IRQ），保持 compiled |

#### Safe HAL MIR 路线（app 侧批量迁移）

> 与上表传统 Rust→C 翻译器路线并行：case 的 `main.rs` 改写为**纯 Safe HAL**
>（无 unsafe、无直接 FFI），实际目标对象来自 `crates/rust-api` 对应镜像 →
> rustc 优化 MIR → `backend/c28x-mir` 降级 → TI 汇编 → RAM 链接上板。
> 分发器：`tools/verify-safe-hal-case-ram.ps1 -Case <module>/<case>`。

| 日期 | module/case | 镜像符号 | 验证证据 | 结果 |
|---|---|---|---|---|
| 2026-09-22 | gpio/gpio_output_basic | rust_gpio34_output_basic | MUX=0 DIR=1 DATA 三段 | PASS |
| 2026-09-23 | gpio/gpio_output_readback_basic | rust_gpio34_output_readback | Rust `is_high/is_low` -> MIR `GPBDAT` 检查；C harness 快照 1→0→1 | PASS |
| 2026-09-22 | gpio/gpio_toggle_basic | rust_gpio34_toggle_basic | DATA 8 次翻转 | PASS |
| 2026-09-22 | gpio/gpio2_3_low | rust_gpio2_3_low | DATA2/3 低电平 | PASS |
| 2026-09-22 | gpio/gpio30_low | rust_gpio30_low | DATA30 低电平 | PASS |
| 2026-09-22 | integration/safe_hal_control_loop | rust_main | ADC→PWM→GPIO 闭环 | PASS |
| 2026-09-22 | gpio/gpio_direction_switch_basic | rust_gpio34_direction_switch | MUX=0 DIR=1 DATA=0 QSEL=Sync PUD=enabled | PASS |
| 2026-09-23 | gpio/gpio_mux_basic | rust_gpio0_mux_to_epwm1a / _restore_gpio | **两阶段快照：phase1 MUX=1（EPWM1A）phase2 MUX=0（GPIO）** | **PASS** |
| 2026-09-23 | adc/adc_sample_basic | rust_adc_sample_basic | ADCRESULT0=1347 sample_count=1 timeout_count=0 | PASS |
| 2026-09-23 | epwm/epwm_cmp_basic | rust_epwm_cmp_basic | GPIO0 MUX=1 TBPRD=4095 CMPA=2048 | PASS |
| 2026-09-23 | timer/timer0_periodic_basic | rust_timer0_periodic_basic | GPIO30 DIR=1 interrupt_count=8 TIE=1 PIE_INTX7=1 vector match | PASS |

> 2026-09-30 说明：**通信时序型 case 的 Rust 化现状与纵向样板**。
> SPI/SCI/I2C/LIN 的 `*_setup()` 入口在 `c28x-mir` 里走 `MirOperation::VoidCall`，
> 实际生成 `f28035_system_init()` + `LCR f28035_<module>_<case>` —— 真正的收发时序、
> FIFO 轮询、字节解包、失败码**仍在 C bridge**（`sdk/c-abi/f28035_bridge.c`）。
> 真正"Rust PAC 直出"的只有直线读写的 `*_reg_if_rw_basic`。
> 本次为 `spi_internal_loopback_basic` 把时序逻辑下沉为 Rust：
> `sdk/f28035-safe-hal/src/pac.rs::spi::run_internal_loopback` + `unpack_rx_byte`
> + `LoopbackResult`，并用 6 个 host 测试对每个失败分支的失败码做 1:1 断言
> （`cargo test -- --test-threads=1`：44 host + 15 doctest 全绿）。
> **边界（不可夸大）**：该 Rust 序列尚未经 C28x 后端降低为目标代码，
> 也未上板取 `status=1 && fail_code=0`，因此 `spi/internal_loopback_basic`
> 的 target 路径**仍保留 C 兜底**、case.toml 状态不变；Rust 序列是待补的
> 后端里程碑。"Rust 化"= 主机可验证的 1:1 语义 + 保留 C 上板兜底，非"已删 C"。
>
> **A 类（寄存器 readback）已全部落地 host 可验证 driver**（`pac.rs`）：
> `spi::run_spi_reg_rw` / `sci::run_sci_reg_rw` / `i2c::run_i2c_reg_rw` /
> `lin::run_lin_reg_rw`，各配 pass + 首个 fail 分支的 host 断言
> （`HostMmio` + `FaultBus` 故障读回）。这些 driver 是 1:1 复刻对应 C
> `*_reg_if_rw_basic` 的寄存器写/掩码读回/失败码，`cargo test --
> --test-threads=1` 共 52 host + 15 doctest 全绿。I2C driver 覆盖到
> 最后一个确定性检查（0x7F21），末位 `sink` liveness 门保持 board-only。
> **target 路径不变**：上板仍走 C bridge 的 `f28035_<module>_reg_if_rw_basic`，
> 这些 driver 只是主机可验证语义 + 待后端降低的里程碑；未上板，case.toml 不改。
| 2026-09-23 | gpio/gpio_mux_dynamic_switch_basic | rust_gpio0_mux_to_epwm1a / _restore_gpio | 复用 gpio0-mux harness:phase1=1 phase2=0 PASS | PASS |

> 2026-09-23 说明：`gpio_mux_basic` 的 0→1→0 三步中，单次镜像调用只能看到
> 最终态 0，无法证明中间态 1 出现过 —— 因此拆成两个镜像（phase1 切 EPWM1A、
> phase2 恢复 GPIO），C harness 在两次调用之间重置一次性外设锁
> （`f28035_peripherals_taken = 0`），分阶段快照 GPAMUX1.GPIO0 完成验证。
> 后端 `GpioStep::SetMux` + `GpioMux` 分类器 + `.ref f28035_gpio_set_mux` 为本
> case 新增；`gpio_mux_dynamic_switch_basic` 同能力可顺带覆盖。

下面 §8 保留的是早期 117 条 scaffold 的历史快照，其中一部分后来已推进。
当前剩余 63 条，实时明细必须从 `case.toml`/`report-status.ps1` 获取。

### 8. 早期未迁移清单（历史快照：当时 117 条）

- **adc(5)**：adc_int_continuous_mode, adc_int_noncont_overflow, adc_reg_rw_smoke, adc_reset_semantics, adc_socctl_config_sweep
- **can(7)**：can_extid_filter_basic, can_global_mask_opcode_shadow_basic, can_interrupt_dual_line_basic, can_mailbox32_shadow_sweep_basic, can_rx_extid_dlc_sweep_basic, can_selftest_mode_toggle_basic, can_status_flag_clear_basic
- **ecap(10)**：ecap_apwm_matrix, ecap_capture_continuous_wrap, ecap_capture_counter_reset, ecap_capture_dual_edge, ecap_capture_prescale_div2, ecap_capture_quad_edge, ecap_capture_single_edge, ecap_capture_wrap_matrix, ecap_interrupt_integration, ecap_reg_rw_smoke
- **epwm(1)**：epwm_reg_rw_smoke
- **eqep(10)**：eqep_compare_output_pulse, eqep_count_basic, eqep_interrupt_gate, eqep_mode_test, eqep_polarity_test, eqep_register_wr, eqep_reset_fsm_matrix, eqep_unit_timeout_test, eqep_unit_timer, eqep_watchdog_timeout_test
- **gpio(0)**：~~gpio_pin_walk_basic~~ (→verified), ~~gpio_xint_falling_basic~~ / ~~gpio_xint_rising_basic~~ (→compiled, 外部跳线依赖) —— B1 批次已消化
- **hrcap(10)**：hrcap_capture_fifo_matrix, hrcap_clock_softreset_matrix, hrcap_counter_overflow_matrix, hrcap_dual_instance_gpio_matrix, hrcap_hr_capture_fall, hrcap_hr_capture_rise, hrcap_interrupt_enable_clear_matrix, hrcap_normal_capture_fall, hrcap_normal_capture_rise, hrcap_reg_rw_smoke
- **i2c(10)**：i2c_master_addr_nack_stop_basic, i2c_master_read_1byte_basic, i2c_master_read_8byte_basic, i2c_master_read_back_to_back_basic, i2c_master_reg_readback_sweep, i2c_master_repeated_start_write_then_read_4byte_basic, i2c_master_write_1byte_basic, i2c_master_write_8byte_pattern, i2c_master_write_back_to_back, i2c_master_write_then_read_4byte_basic
- **jtag(1)**：et_jtag
- **lin(10)**：lin_baud_program_basic, lin_header_break_sync_master_basic, lin_iodft_loopback_basic, lin_reg_if_rw_basic, lin_rx_checksum_length_real_basic, lin_rx_rxcnt_num_boundary_real_basic, lin_sci_multibuf_rdslot_sweep_basic, lin_top_mode_loopback_power_cross_basic, lin_tx_checksum_ext_real_basic, lin_wakeup_break_flag_route_basic
- **pie(10)**：pie_irq_ack_holdoff_release_basic, pie_irq_single_source, pie_mask_ack_basic, pie_regs_xint_readhit_mode_counter_basic, pie_soc_direct_cpu_irq_nmi_timer_basic, pie_soc_gpio_xint123_basic, pie_vector_table_fill_u16_basic, pie_vector_table_fill_u32_basic, pie_vector_table_rw_inline_u16_basic, pie_xint_counter_readmux_basic
- **sci(10)**：sci_baud_program_basic, sci_fifo_reset_then_loopback_basic, sci_fifo_rx_basic, sci_internal_loopback_basic, sci_loopback_data_pattern_basic, sci_reg_if_rw_basic, sci_rxrdy_clear_on_read_basic, sci_sciccr_charlen_sweep_basic, sci_stop2_parity_charlen_sweep_basic, sci_txrdy_int_nonfifo_basic
- **spi(0)**：B1 批次已消化，10 个全部 → `compiled`（构建通过；`SpibRegs` 别名已补入 `f28035-rust-bridge/firmware/F28035_Peripheral_symbols.cmd`，JTAG 待后续批量验证）
- **sys_clk(10)**：sys_divsel_roundtrip_basic, sys_intosc2_pll_basic, sys_lpm_idle_interrupt_basic, sys_lpm_reg_access_basic, sys_osc1_osc2_roundtrip_basic, sys_pll_bypass_basic, sys_pll_lock_basic, sys_reset_release_basic, sys_xclkout_div_basic, sys_xrs_runtime_window_basic
- **wdg_sys(10)**：sys_lpm_idle_watchdog_basic, sys_watchdog_timeout_basic, sys_watchdog_timeout_reset, sys_wdg_wdchk_wrong_key, watchdog_disable_test, watchdog_intr_mode_test, watchdog_key_sequence_test, watchdog_prescaler_test, watchdog_reset_mode_test, watchdog_wdflag_test

### 9. 失败记录

（烧录失败 / TIMEOUT 的 case 在此登记：case、时间、TEST_FAIL_CODE、原因、处置）

| 时间 (UTC+8) | module/case | TEST_FAIL_CODE | 原因 | 处置 |
|---|---|---|---|---|
| 09-21 11:12 | epwm/epwm_tz_external_tz1_ost | 0xEE03 (OST_NOT_SET) | 源 C 依赖 UVM 把 GPIO15/TZ1n 拉低触发 OST；裸板无外部激励，TZFLG.OST 永不置位 | 属**外部激励依赖型**，保持 `compiled`，不强行 verified；需 FPGA/UVM 侧拉 GPIO15 后复验 |
| 09-21 11:14 | gpio/gpio_input_basic | 0x0402 (FAIL_LOW) | 源 C 要求 GPIO30 接线到 GPIO0（Rust 注释明示）；板上无跳线，写 0 后回读非 0 | 属**外部接线依赖型**，保持 `compiled`；需 30↔0 跳线后复验 |
| 09-21 11:18 | epwm/epwm_reg_rw_smoke（首次） | 0x3248 (HRPWR_5555) | HRCNFG/HRPWR/HRPCTL 为 HRPWM power/config 寄存器，裸板未使能 HRPWM 时钟时不可写，掩码 RW 读回不符 | 裁剪 HR 电源/配置 16-bit RW（0x3246–0x324B）+ HR mirror（0x324C/D）+ packed-32（0x324E/F）断言，保留 reset 值检查与标准 RW 扫描（0x3201–0x3245）；**11:22 复验 PASS** → `verified` |
| 09-21 11:30 | gpio/gpio_pin_walk_basic | —（PASS） | A 组(0..31)+B 组(32..44) 逐脚驱动、mux/qsel 扫描、复位回读全通过 | 纯内部自检，**烧录 PASS**（status=1, fail_code=0）→ `verified` |
| 09-21 11:32 | gpio/gpio_xint_falling_basic | 0x0901 (FAIL_IRQ) | 需 GPIO30→GPIO0 跳线，板上未接 → XINT1 下降沿未触发，ISR 计数为 0 | 属**外部接线依赖型**，C-ABI 封装已忠实复刻源 C（fail code 与源 `case_config.h` 一致）；保持 `compiled`，接跳线后复验 |
| 09-21 11:33 | gpio/gpio_xint_rising_basic | 0x0801 (FAIL_IRQ) | 需 GPIO30→GPIO0 跳线，板上未接 → XINT1 上升沿未触发，ISR 计数为 0 | 属**外部接线依赖型**；保持 `compiled`，接跳线后复验 |

#### 经验沉淀（供后续批次复用）

1. **翻译器子集硬约束**：`rust_main()` 无参、void、函数体恰好一个 `unsafe{}`；FFI 实参只能是 **u16 字面量**；不能传 local 变量、不能写 for/while。因此**循环/寄存器扫描/动态 fail code 必须下沉到 C-ABI**（C 封装内部自包含 `test_pass/fail`，void 返回）。
2. **主文件只含 `rust_main` 一个函数**：`rust_timer0_interrupt` 由 `app/firmware/default_interrupts.c` 提供（每个 case 都链接它）。翻译器要求"恰好一个 Rust 函数"，主文件再定义该符号会链接冲突。
3. **HRPWM 寄存器板上不可写**：HRCNFG/HRPWR/HRPCTL 及 HR mirror/packed-32 依赖 HRPWM 时钟使能，裸板 smoke 测试应只保留其 reset 值检查，不做掩码 RW 断言。
4. **构建脚本的 stderr 误报**：`build-case.ps1` 链接阶段 `code_start` 入口警告会写入 stderr，PowerShell 视 NativeCommandError 使退出码非 0，但 `.out` 已正常生成。判定构建成功以 `.out` 时间戳为准，不以脚本退出码为准。
5. **JTAG 闭环判定**：`TEST_STATUS=1 && FAIL_CODE=0` = PASS；`TEST_STATUS=2` = FAIL（打印 EPWM1 寄存器）；外部依赖型 case 即便 FAIL 也说明管道已打通，应记录为"需外部激励/接线"而非迁移缺陷。

---

<a id="a-6"></a>

## 工程优化清单与执行顺序

> 原文：`f28035-rust-bridge/docs/OPTIMIZATION_PLAN.md`；SHA-256：`2a4077df12d202c3e3e242105e67414b8741642719615e467d391ea4407683e6`。

> 更新日期：2026-10-19
> 本文档基于 `f28035-rust-bridge` 合并后的实际核查，列出值得优化的点，
> 按 **成本低→收益高、依赖前置→依赖后置** 排序。

> 说明：本文后半部分保留了应用/PATH A 的历史批量迁移计划。当前编译器主线已经
> 转离 MIR，编译器侧的实时状态以编译器路线自己的文档和验证脚本结果为准。

### 编译器侧历史优化项

旧独立 `llc` 交付路线已于 2026-10-21 迁出活动工程。本节后续只维护 PATH A
应用、Safe HAL 和 MIR 工作；编译器工作统一由 B-1 路线维护。

### 优先级总览

| 阶段 | 主题 | 状态 |
|---|---|---|
| **P0** | 工程卫生 | ✅ 已完成 |
| **P1** | 自动化与可信度 | ✅ 大部分完成 |
| **P2** | Safe HAL 纵向样板 | ✅ 已完成 |
| **P3** | case 状态推进 | ✅ 146/146 全部处理 |
| **P4** | 代码组织（按外设拆模块） | ✅ 本轮完成 |
| **P5** | 脚本合并（329→2） | ✅ 已实现（静态校验通过，待真机全量） |

---

### 当前执行状态快照

#### case 覆盖（146/146）

| 状态 | 数量 | 说明 |
|---|---|---|
| verified-via-mir | 136 | 上板 RAM/JTAG 验证通过，called=1 |
| compiled-only | 10 | 代码完整可编译，不上板（硬件风险高） |
| 未处理 | 0 | — |

#### 外设覆盖

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

#### 代码组织（P4 完成）

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

#### C bridge 规模

- `sdk/c-abi/f28035_bridge.c`：4324 行，141 个 void 函数
- 后端 `backend/c28x-mir/src/main.rs`：116 个 classify 条目

---

### 剩余可优化项

#### P5：脚本合并（329 → 2）

**现状（2026-10-19 更新）**：通用脚本已实现，不再依赖逐 case 复制。
- `tools/build-mir.ps1` / `tools/verify-mir.ps1`：从 `tools/mir-cases.json` 读取每 case 字面参数，复刻 legacy 构建/验证序列；标准 case 走通用逻辑，custom case 自动委托原脚本，行为不变。
- `tools/_internal/mir-common.ps1` + `tools/_internal/gen-mir-manifest.py`：共享逻辑与清单生成（142 case，127 标准 + 15 custom，37 个用 `-OnlyExport`）。
- `tools/retire-legacy-mir-scripts.ps1`：默认 `-WhatIf` 预览；`-Apply` 时把标准旧脚本备份到 `tools/_archive/legacy-mir/` 并原地写 3 行转发器，custom 保留，绝不删除。
- 静态校验已通过：`self-check.ps1 -DryRun` 全量比对 **142/142 OK**；5 个 .ps1 均带 UTF-8 BOM 且语法解析零错误。真机全量验证需在装有 TI cl2000/dss + XDS100v1 的机器上跑 `self-check.ps1`（非 DryRun）。

**用法**：
```powershell
## 通用 build（参数从 manifest 读取，无需 -RustFn）
.\tools\build-mir.ps1 -Case spi_triwire

## 通用 verify
.\tools\verify-mir.ps1 -Case spi_triwire

## 全量比对（静态，无需硬件）
.\tools\self-check.ps1 -DryRun

## 全量真机验证（需 TI 工具链 + JTAG）
.\tools\self-check.ps1
```

**收益**：
- 改 bug 只改一处
- 新 case 不用复制模板
- 老脚本里漏加 `-OnlyExport` 的问题（如 spi_triwire）不会再发生

#### P6：harness 合并（152 → 1）

**现状**：每个 case 一个 `platform/firmware/xxx_test.c`，内容都是调 rust_xxx() + called=1 + 死循环。

**目标**：后端 codegen 直接生成 main，或用通用 harness + `-D` 传函数名。

#### P7：self-check 全量覆盖

**现状（2026-10-19 更新）**：`tools/self-check.ps1` 已实现，不再为空壳。它遍历 `tools/mir-cases.json`（142 个 `build-mir-*`/`verify-mir-*` 对应的 case）调用 `verify-mir.ps1`，输出 PASS/FAIL 汇总表与退出码；`-DryRun` 做静态清单/文件一致性检查（**142/142 通过**）；`-Case` 可单跑。注意：Safe HAL 桥接 case（走 `verify-safe-hal-case-ram.ps1`）不在 build-mir/verify-mir 命名下，未纳入本清单。

**目标**：在装有 TI cl2000/dss + XDS100v1 的机器上跑 `self-check.ps1`（非 DryRun），确认 136 个可验证 MIR case 的结果与现状一致，再执行 `retire-legacy-mir-scripts.ps1 -Apply` 归档旧脚本。

#### P8：C bridge 按外设拆

`f28035_bridge.c` 4324 行，类似 P4 的做法按外设拆成多个 .c 文件。

---

### 上板验证路线（已稳定）

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

---

<a id="a-7"></a>

## F28035 Flash / CSM Status

> 原文：`f28035-rust-bridge/docs/HARDWARE_RECOVERY.md`；SHA-256：`3a6251937a723df3481f53348fcf2361234bbbeb09fc338fc432cb9260f5c5d4`。

### Current board status (read-only verification, 2026-09-22)

The connected TMS320F28035 is **not password locked**.

The following observations were made through XDS100v1 and CCS DSS without an
erase, program, unlock, KEY-register write, target reset, or program load:

- CSM password locations `0x3F7FF8..0x3F7FFF` read as eight `0xFFFF` words.
- Reading those eight erased password words completed the normal dummy-read
  sequence; `CSMSCR @ 0x0AEF` then read `0x0070`, so `SECURE` (bit 0) was clear.
- `FSTATUS @ 0x0A83` read `0x0003`: the Flash bank/pump was active in read
  mode and the 3.3-V error latch (bit 8) was clear.
- Valid user-Flash addresses contained existing data (`0x3E8000=0x2111`,
  `0x3F0000=0x1901`, `0x3F6000=0x761B`).

`0x3F8000` is **not user Flash** on F28035. It is the program-space mirror of
L0 SARAM. Values read there describe RAM contents and are not evidence about
Flash health. F28034/F28035 user Flash is `0x3E8000..0x3F7FFF`.

### Why the earlier lock diagnosis was wrong

An erased-password device can appear secure immediately after reset until the
eight password locations have been dummy-read. Treating that transient state as
an unknown-password lock produced the earlier incorrect diagnosis.

The previous `tools/try-flash-load.js` connected and called `loadProgram`
immediately. The guarded GPIO34 programming flow now performs the erased-
password dummy reads, checks that all words are `0xFFFF`, and confirms
`CSMSCR.SECURE == 0` before allowing the CCS Flash loader to run.

### Current Flash workflow

The older `build-mir-gpio34-output.ps1` currently links with
`tools/F28035_ram.cmd`. Its Flash-named wrapper is not evidence of a
persistent image and should not be used to program the board. Use the
one-file build and explicit guarded programming workflow in
`archive/ONE_FILE_MAIN.md` instead.

That workflow builds a separate sector-A image and rejects every loadable
segment outside the sector-A code area or the two-word boot entry. Before
programming it backs up all user Flash and checks erased, unprotected CSM
passwords. Its Flash-only startup copies `ramfuncs` to RAM before calling
`InitFlash()`. After programming, it verifies a Boot-ROM reset without
forcing PC; the physical power-loss test remains a separate manual step.

GPIO34/GPIO37 must select boot-to-Flash at reset. Never interrupt power
during a Flash erase/program operation. Do not use images that contain a
loadable `CsmPwlFile` section.

---

<a id="a-8"></a>

## Zero-C RAM GPIO experiment

> 原文：`f28035-rust-bridge/docs/archive/BARE_RUST_GPIO34_RAM.md`；SHA-256：`1e317c64ff54e4580043c6213bb4d655f87409d6edbc7540bcf5cf9909fac90e`。

This is a RAM-only C28x compiler experiment. Both images link only MIR-derived
Rust assembly and a minimal startup assembly object. No C object or TI C
runtime library is linked, and the verifier does not program flash.

### Reproduce

From the repository root:

```powershell
& tools/verify-zero-c-gpio-ram.ps1
& tools/verify-zero-c-gpio-ram.ps1 -SafeHal
& tools/verify-bare-mmio-reject.ps1
```

The first image uses `crates/bare-gpio34/src/lib.rs`. Its optimized Rust MIR
contains constant physical-word `read`, bitwise modify, and `write` operations.
`backend/c28x-mir` lowers the complete straight-line sequence, including
GPIO2 and GPIO34 configuration, GPIO34 high/low commands, and repeated
configuration. The JTAG verifier first places both pins high and changes their
MUX and direction, then requires both to be GPIO outputs reading low and the
CPU to be at `bare_idle`.

The second image starts at `rust_safe_gpio34_low` in the existing
`sdk/f28035-safe-hal` crate. Its Rust source calls `Peripherals::take`,
`Gpio::output::<34>`, and `OutputPin::set_low`. rustc type-checks this code;
the MIR backend checks the call pattern and emits the corresponding GPIO34
register instructions. The JTAG verifier checks GPIO34 MUX, direction, data,
and idle PC. This is a typed Safe HAL **entry** in a zero-C image, but the
backend still replaces the HAL call chain with a recognized sequence rather
than compiling the HAL implementation generically.

The rejection check confirms that a branching raw-MMIO body and a changed
Safe HAL `set_high` action both fail lowering. The build scripts also reject
external references in generated assembly and libraries/C objects in the map.

### Current boundary

- `WordAddress` uses a physical C28x word address. Its Rust volatile-pointer
  method bodies are not generically lowered; the accepted MIR sequence is
  lowered by this out-of-tree backend.
- The Safe HAL image does not yet execute `Peripherals::take` ownership state
  or the ordinary `OutputPin` method bodies on target. Its one-shot entry is
  type-checked, then the backend emits equivalent GPIO register effects.
- All peripheral ownership handles now have private constructors and do not
  implement `Copy` or `Clone`; validated SPI/SCI/I2C result tokens remain
  copyable values with private constructors. Host `compile_fail` tests reject
  forged and duplicated handles. This source-level safety improvement does
  not prove that the ownership state machine runs in the zero-C image.
- The next target gate must execute two `take()` calls and a duplicate GPIO34
  claim from the actual HAL implementation, then verify the second take and
  claim fail while the first handle can still drive the pin low. The current
  GPIO34 pattern classifier cannot satisfy that gate.
- A separate zero-C RAM pilot now executes a reusable Rust `Once::acquire`
  method and a Safe Rust caller that checks first-success/second-failure for
  two ownership words, then invokes its own safe Rust GPIO34 `set_low` method
  on silicon. See `OWNERSHIP_ONCE_RAM.md`; it uses local pilot types, not yet
  the existing HAL's `take`, `claim`, or `set_low` methods.
- Startup, stack setup, and watchdog disable still come from a small C28x
  assembly file — that file is now the runtime (`crates/c28x-rt/asm.s`), and it
  also programs the PLL (60 MHz) and copies the PIE table before `main`.
  CCS/XDS100 and TI assembler/linker remain build/debug tools.
- There is no general Rust ABI, arbitrary control flow, or full `core` support
  for the C28x target yet. Interrupt entry and runtime startup do exist now
  (see the compiler route's runtime section): `crates/c28x-rt/interrupts.s`
  supplies the ISR prologue/epilogue and `IRET`, verified on silicon.

Recorded results: `BARE_GPIO_MULTI_RAM=PASS`,
`SAFE_HAL_GPIO34_ZERO_C_RAM=PASS`, `UNSUPPORTED_MMIO_REJECT=PASS`, and
`SAFE_HAL_ACTION_REJECT=PASS`.

---

<a id="a-9"></a>

## One-file Rust application pilot

> 原文：`f28035-rust-bridge/docs/archive/ONE_FILE_MAIN.md`；SHA-256：`194971706921c0a2bcd9381c2b4bde9555ad7b2049919478a4607be171b7d3b8`。

Edit `app/src/main.rs` and run from the repository root:

```powershell
& tools/run-user-main.ps1
& tools/run-user-main.ps1 -Verify
& tools/verify-user-main-reject.ps1
```

The RAM route above remains the default and never programs Flash. To build a
separate persistent image from the same `app/src/main.rs` without touching the
board, run:

```powershell
& tools/build-user-main-flash.ps1
```

This first rebuilds the RAM reference, then links
`build/user-main-flash/user_main_flash.out` into Flash sector A with
`codestart` at the Boot-ROM Flash entry. The Flash-only harness copies TI's
`ramfuncs` into RAM and runs `InitFlash()` before calling the Rust entry.
The build rejects loadable segments outside sector A and the two-word boot
entry, including the CSM password area.

Programming is a separate, destructive operation. It erases Flash sector A,
so first confirm that replacing the current image is intended and that the
GPIO34/GPIO37 boot straps select boot-to-Flash. The command requires an
explicit switch, rebuilds and audits the image, saves a full user-Flash
backup, checks erased/unprotected CSM state, programs with CCS
`Erase, Program, Verify`, then verifies a Boot-ROM reset without forcing PC:

```powershell
& tools/program-user-main-flash.ps1 -ConfirmFlashErase
```

The backup defaults to `backups/user-flash-before-<timestamp>.bin` and must
contain all 0x10000 user-Flash words before programming begins. A custom
location can be supplied with `-BackupFile`.

After physically removing and restoring power, verify persistence without
programming or loading any code (the `.out` is used for symbols only):

```powershell
& tools/verify-user-main-flash.ps1
```

The Flash verifier currently checks the GPIO30/GPIO34 sample and return value
`0xFFFD`. If the application behavior changes, update both the RAM and Flash
verifiers. A build-only PASS is not a claim that Flash programming or cold boot
has passed on hardware.

This route selects the `one-file-main` feature. The separate
`crates/rust-api/src/user_main.rs` remains untouched and is not compiled by
this command.

The normal build compiles `sdk/c-abi/f28035_bridge.c` from source and links
the project's default Timer0 callback. A diagnostic `-BridgeObject` override
can select a prebuilt object, but it does not validate the current C source.

The first command runs host Rust tests, type/borrow-checks the application via
rustc MIR, lowers the supported `rust_user_main` body to C28x assembly, and
links `build/user-main/user_main_ram.out` with the TI compiler and the C ABI
bridge and default interrupt callback. It checks the linked image's loadable
segments for flash and CSM
password-area overlap. `-Verify` loads this RAM image over XDS100 and checks
the current example's GPIO30/GPIO34 MUX, direction, and data snapshots. It
does not program flash. The C harness and startup are project infrastructure;
application authors edit only `app/src/main.rs`.

The current `rust_user_main` backend gate accepts scalar `u16`/`bool` locals,
`Add`, `Sub`, `Mul`, `BitAnd`, `BitOr`, `BitXor`, unsigned comparisons, and
`bool -> u16`, plus basic-block branches, loops, a `u16` return value, and
0-2 scalar-argument `f28035_*` calls in the PAC/FFI layer. The example
configures GPIO30 and GPIO34 as outputs, runs a five-iteration loop, reads
GPIO30, then calculates and returns `0xFFFD`; an unsigned comparison also
sets GPIO34 high. The C harness and JTAG verifier read the exact return
value. Calls go through the Rust API in `crates/rust-api`, then the existing
narrow C ABI. The separate `sdk/f28035-safe-hal` crate is not yet the input
to this pilot.

This is **not** a general Rust compiler. Heap allocation, arbitrary Rust
types/operators, callbacks, interrupts, and unvalidated peripheral calls do
not lower through this gate yet. An unsupported MIR shape fails the build; it
is not silently reduced to a list of C calls. The rejection command checks
this with unsupported atomic and division fixtures. If the application's pins
or expected output change, adapt the example-specific JTAG assertions in
`user_main_test.c` and
`verify-user-main.js`; the build command itself still only reads `main.rs`.

---

<a id="a-10"></a>

## C28x Rust ownership method RAM pilot

> 原文：`f28035-rust-bridge/docs/archive/OWNERSHIP_ONCE_RAM.md`；SHA-256：`a3f0dc3e367640576b8272a0039eb1bdca264531c98b5f1ffadc15f0b9ecba1a`。

This is a zero-C, RAM-only path-2 experiment. `crates/ownership-gpio34`
defines one reusable Rust method, `Once::rust_once_acquire(&self) -> u16`.
Its optimized MIR contains `AtomicU16::compare_exchange(0, 1, SeqCst,
SeqCst)`, a success check, and a `u16` result. A Safe Rust application
`rust_ownership_application` calls `Peripherals::take()` twice and
`Gpio::claim34()` twice; both wrapper methods are inlined into the optimized
MIR. Its first claimed handle then calls a safe Rust
`OutputPin34::rust_gpio34_set_low(&mut self)` method. The backend lowers that
caller's calls and success/failure branches, the reusable acquisition method,
and the pilot GPIO method's volatile register actions. Two RAM words represent the
peripheral-root and GPIO34 claims. The startup assembly only initializes
them, calls the Rust application, and records its `u16` return value.

Run from the repository root:

```powershell
& tools/verify-ownership-once-ram.ps1
& tools/verify-ownership-reject.ps1
```

Expected JTAG observations are `APPLICATION_RESULT=1`,
`OWNER_FLAGS=1,1`, GPIO34 `MUX=0`, `DIR=1`, `DATA=0`, and
`RUST_ONCE_METHOD_RAM=PASS`. Three negative tests change the Rust
compare-exchange expected value, reverse the application's second-take
branch, or replace the GPIO clear mask; the backend must reject all changed
MIR shapes.
The link map must contain only `ownership.obj` and `start.obj`, with no C
object or runtime library.

### Boundary

- Both the method body and a Safe Rust caller are lowered from optimized MIR
  and executed on F28035. The backend still recognizes their exact patterns;
  this is not generic Rust control-flow or atomic code generation.
- The pilot's `Peripherals::take`, `Gpio::claim34`, and GPIO output method are
  small local types in `crates/ownership-gpio34`, not the production implementations in
  `sdk/f28035-safe-hal`. The latter still do not execute on target in the
  existing zero-C GPIO34 image.
- The generated application passes the two RAM-word addresses in XAR4 to
  the generated acquisition method. Startup still initializes the words and
  records the application result in assembly.
- Startup sets INTM before any call and never enables interrupts. The emitted
  read/conditional-write implements this single-core RAM pilot only; it is
  not a general interrupt-safe `SeqCst` implementation.
- TI assembler/linker and XDS100/DSS remain the build and verification tools;
  flash is untouched.

Next target gate: replace the pilot wrappers and GPIO method with the existing
Safe HAL's `Peripherals::take`, `Gpio::claim`, output configuration, and
`set_low` path in the same zero-C image.

---

<a id="a-11"></a>

## 架构：应用路径与 MIR 后端

> 来源：2026-10-20 从编译器路线文档的 Architecture 章节迁入（原文
> `f28035-rust-bridge/docs/ARCHITECTURE.md`，SHA-256：
> `b3f5ce426848dd9757b7b2d17cfff5cc36e4f53d0f8bcd09cc9b0e91283f7941`）。
> 编译器侧内容已经迁出；此处只保留应用路径（Track 1）与 PATH 2A 的原文。

### Track 1: Application Development

```
app/ Rust case
  -> sdk/f28035-safe-hal safe API
  -> sdk/c-abi narrow C bridge
  -> TI headers / startup / linker scripts / C2000 support code
  -> tools/build-case.ps1
  -> TI CGT .out
  -> CCS/XDS100 RAM or Flash load
  -> JTAG verification
```

This is the engineering path for board bring-up and product-style cases.  It is
allowed to keep CCS, TI CGT, TI headers, startup files, linker scripts and a
small audited C ABI underneath the HAL.  Its safety value comes from making the
application/control layer use Safe Rust handles instead of raw C calls or naked
register writes.

Current status:

- The build and JTAG verification flow is usable.
- Seven GPIO cases are formal Safe HAL bridge cases: `gpio_output_basic`,
  `gpio_output_readback_basic`, `gpio_toggle_basic`, and
  `gpio_direction_switch_basic`, plus `gpio2_3_low`, `gpio30_low`, and
  `gpio_mux_basic`.  They are tracked in the app case registry, their app
  sources use the Safe HAL, and `tools/verify-safe-hal-case-ram.ps1` verifies
  the target through rustc MIR -> `backend/c28x-mir` -> RAM/JTAG.
- `integration/safe_hal_control_loop` extends the bridge beyond GPIO: ADC0
  samples drive ePWM1 CMPA and GPIO31, while Timer0 periodic interrupts are
  verified by the RAM/JTAG control-loop harness.
- Three focused non-GPIO bridge cases are also verified through the same route:
  `adc/adc_sample_basic`, `epwm/epwm_cmp_basic`, and
  `timer/timer0_periodic_basic`.
- Most other app hardware cases still use direct `extern "C"`/`unsafe` or the
  restricted Rust-to-C translator path; they should not yet be described as
  fully Safe Rust end-to-end.
- The next application-track milestone is to add GPIO input/loopback and then
  extend the same Safe HAL bridge pattern to communication/capture peripherals.

### PATH 2A: How the current MIR backend works

#### 1. PAC layer (`crates/rust-api/src/pac.rs`)

The PAC defines a trait `MmioBus` with three operations:

```rust
trait MmioBus {
    fn write_word(&mut self, addr: u16, val: u16);
    fn read_word(&mut self, addr: u16) -> u16;
    fn modify(&mut self, addr: u16, mask: u16, bits: u16);
}
```

Two implementations:
- `HostMmio` (cfg(test)) — a HashMap-based fake for host unit tests
- `C28xMmio` (cfg(not(test))) — volatile pointer reads/writes

Typed register wrappers (`OutputConfig`, `UpCountConfig`, etc.) call these
methods with **compile-time constant addresses**.

#### 2. The MIR analyzer (`backend/c28x-mir/src/main.rs`)

The analyzer runs as a `rustc_driver` callback.  For each function in the
crate, it walks the MIR and classifies what kind of function it is:

| Classifier | Recognizes | Emits |
|---|---|---|
| `classify_platform_control_loop` | The main control loop shape (20 f28035_* calls) | Inline MMIO + LCR to typed apply |
| `classify_mmio_write_sequence` | Straight-line `write_word` / `modify` / `write_u32` calls | XAR-indirect C28x stores |
| `classify_interrupt_callback` | Timer0 ISR pattern | PIE ack + clear eoc |
| `classify_safe_hal_adc_sample_basic` | `system_init` + `Peripherals::take` + one ADC sample call | ADC SOC0 sample sequence |
| `classify_safe_hal_epwm_compare_basic` | `system_init` + `Peripherals::take` + ePWM configure/set_compare | ePWM1A period/CMPA setup |
| `classify_safe_hal_timer0_periodic_basic` | `system_init` + `Peripherals::take` + Timer0 periodic start | Timer0 vector/periodic interrupt setup |
| `Max` / `Min` | Control loop arithmetic | CMP + conditional branch |

#### 3. MMIO lowering variants

The backend recognizes five MMIO patterns:

| Variant | MIR shape | Generated asm |
|---|---|---|
| `Imm` | `write_word(bus, const_addr, const_val)` | `MOVL XAR4,#addr; MOVB AL,#val; MOV *XAR4,AL` |
| `Acc` | `write_word(bus, const_addr, val_from_arg)` | `POP ACC; MOVL XAR4,#addr; MOV *XAR4,AL` |
| `Modify` | `addr.modify(bus, mask, bits)` | `MOV AL,*XAR4; AND/OR; MOV *XAR4,AL` |
| `WriteU32` | `Register32::write_u32(bus, val)` | `MOV *XAR4,AL; MOV *+XAR4[1],AH` |
| `ReadIndirect` | `read_word(bus, runtime_addr)` | `MOV AL,*XAR4` |

**Key insight**: rustc's `-Zmir-opt-level=4` propagates the `TiWordAddress(26624_u16)`
constant into the call operand, so the backend can extract the physical
address directly without needing a general constant folder.

#### 4. XAR indirect addressing (critical hardware lesson)

Early attempts used `MOVW DP, #page; MOV @offset, AL` — this failed on real
silicon because the TI assembler resolves `@0x00` to absolute address 0,
not DP-relative.  The working approach is **XAR indirect addressing**:

```asm
MOVL XAR4, #0x6805    ; absolute 22-bit address
MOV *XAR4, AL         ; indirect store
```

This bypasses DP entirely and works reliably.

#### 5. EALLOW/EDIS auto-wrap

If any MMIO step touches an address in `0x7000-0x70FF` (SysCtrl/GpioCtrl/PieCtrl),
the backend automatically wraps the sequence in `EALLOW`/`EDIS`.



### MIR 路线当前状态

- `backend/c28x-mir` has produced C28x assembly/object code for selected
  `crates/rust-api` functions and passed RAM/JTAG hardware checks.
- `app/src/main.rs` is a one-file application pilot included by `crates/rust-api`.
  The `one-file-main` feature keeps it separate from the existing
  `crates/rust-api/src/user_main.rs`. The strict MIR gate accepts selected
  16-bit arithmetic, comparisons, branches, loops, returns, and Safe HAL GPIO
  calls. RAM/JTAG confirms the exact computed return value and GPIO30/GPIO34
  states. Unsupported MIR is rejected. The normal build compiles the restored
  C bridge source and links the default Timer0 callback（原 `ONE_FILE_MAIN.md` 已并入第 8 节）。
- The same one-file source also has a separate build-only Flash link path.
  It reuses the verified Rust/C objects, adds a Flash-only `ramfuncs` copy and
  `InitFlash()` step, and audits Flash load segments and the Boot-ROM entry.
  RAM/JTAG remains the default; Flash programming and power-cycle proof are
  separate explicit hardware steps, not implied by a successful build.
- A separate RAM-only ownership pilot now lowers one Rust
  `AtomicU16::compare_exchange(0, 1)` method body and a Safe Rust caller for
  two RAM resources, followed by a pilot safe Rust GPIO34 `set_low` method.
  JTAG confirms first-success and second-failure for both resources and GPIO34
  output low. These are pilot types, not the existing Safe HAL path（原 `OWNERSHIP_ONCE_RAM.md` 已并入第 9 节）。
- Verified examples include GPIO low/output cases, the MIR control loop,
  independent ADC/ePWM/Timer0 Safe HAL cases, GPIO34 output, GPIO39 low, and a
  RAM-only GPIO sweep harness.
- `gpio_output_readback_basic` now keeps the readback assertion in Safe Rust:
  `OutputPin::is_high/is_low` is recognized by the MIR backend and lowered into
  GPIO34 `GPBDAT` checks before the C harness records its final JTAG snapshot.
- The GPIO sweep currently proves GPIO0..34 and GPIO39..44 under JTAG.  GPIO35
  through GPIO38 are JTAG pins on this setup; strict all-45 physical pin freedom
  is not claimed while the debugger is attached.


### MIR 路线的硬件验证

本节记录 MIR 路线（PATH 2A）的硬件验证方式。历史 `build/mir*` 产物已移除，
命令保留作复现参考；编译器路线的验证入口不在本文范围。

The project uses XDS100 via TI DSS/CCS scripts.  Current verified MIR-track
hardware evidence includes:

```powershell
.\tools\flash-and-verify-mir-control-loop.ps1 -SkipBuild
.\tools\verify-mir-gpio-sweep.ps1 -SkipBuild -AllowJtagPins
```

The control-loop verifier (`tools/verify-mir-control-loop.js`) reads:
- `AdcResult0` ≈ 2926
- `CMPA` ≈ ADC value
- `TBPRD` = 4095
- `tracking_error` = 0

The GPIO sweep verifier prints a per-pin table:

- strict GPIO0..44 mode intentionally fails while JTAG occupies GPIO35..GPIO38;
- `-AllowJtagPins` mode passes GPIO0..34 and GPIO39..44, with MUX/DIR and
  low/high readback recorded.

---

