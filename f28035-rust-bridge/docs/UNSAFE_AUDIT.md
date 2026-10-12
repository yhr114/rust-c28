# Unsafe 审计清单

> 生成日期：2026-09-21。任何新增/修改 `unsafe` 后须同步更新本文。

## 统计

| 文件 | `unsafe` 块 | `pub unsafe fn` | 说明 |
|---|---:|---:|---|
| `sdk/f28035-safe-hal/src/lib.rs` | 24 | 0 | 全部在安全 API 内部调用 C bridge |
| `sdk/f28035-safe-hal/src/pac.rs` | 67 | 70 | FFI 层：target 路径 + host stubs |
| **合计** | **91** | **70** | |

## 逐项说明

### lib.rs（安全 API 层，调用 C bridge）

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

### pac.rs（FFI 层）

`pub unsafe fn` 共 70 个，分两组：

**Target 路径（`#[cfg(not(test))]`）：34 个**
- 每个函数体仅包含固定地址的 MMIO 读写（`C28xMmio` + `TiWordAddress`），不做地址计算；
- 地址常量来自 TI 寄存器头（DSP2803x_*.h），已交叉验证；
- 调用前提由 HAL 层 const-generic assert 保证。

**Host stubs（`#[cfg(test)]`）：36 个**
- 确定性内存模型（`AtomicBool` / `AtomicU16` / `AtomicU64`），无裸指针；
- 用于 `cargo test` 验证 HAL 类型状态机。

## 不含的 unsafe 类别

| 类别 | 状态 |
|---|---|
| `static mut` | **已清零**（原 `HOST_CMPA` 改为 `AtomicU16`） |
| `mem::transmute` | 无 |
| 裸指针运算（`addr + N`） | 无，所有地址为编译期常量 `TiWordAddress` |
| `std::ptr::read/write` | 无 |
| 动态数组/slice 跨 FFI | 无 |

## 修改规则

- 新增 `unsafe` 必须对应上表一行，填写调用前提/资源所有权/并发条件/返回值约束；
- `lib.rs` 中不允许新增 `extern "C"` 声明（FFI 收拢在 `pac::ffi`）；
- 应用层（`app/hardware-tests/*/src/main.rs`）不允许 `unsafe`，仅通过 `f28035-safe-hal` 安全 API 操作外设。
