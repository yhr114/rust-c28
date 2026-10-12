# 临界区与中断共享规则

> 定义于 2026-09-21。C28x 是单核，无 cache 一致性问题；风险集中在
> 主循环与 ISR 对**同一寄存器/全局变量**的并发读写。

## 1. 资源所有权与 ISR 的边界

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

## 2. 临界区（C28x 无硬件互斥，用 DINT/EINT）

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

## 3. 中断共享状态的可变全局

- **禁止** `static mut`（HAL 已清零；`cargo test` 依赖的 host 原子变量
  是 `#[cfg(test)]` 例外，不上 target）。
- 主循环与 ISR 共享的可变计数器/标志，若将来需要，使用
  `core::sync::atomic` 的 `AtomicU16`（C28x 上对齐 u16 原子读/写），
  并在 `UNSAFE_AUDIT.md` 记录其访问上下文。当前 HAL 尚未暴露此类共享量。

## 4. ISR 包装约定

- TI C ISR 拥有 C28x 中断 ABI 序言/尾声（保存/恢复现场、`IER`/`EINT`
  处理、`RTI`）；Rust 侧 `rust_timer0_interrupt` 只做业务（ack + 业务逻辑）。
- Rust ISR 体**不得**：分配内存、调用可能阻塞的 IO、写日志、超过一个
  共享寄存器的 RMW。
- 每个 ISR 包装的寄存器副作用必须在 `UNSAFE_AUDIT.md` 的 FFI 表中标注
  "可在 ISR 上下文调用 = 是/否"。

## 5. 审计检查点

| 检查项 | 现状 |
|---|---|
| HAL 是否含 `static mut` | 否（已清零，改 `AtomicU16`） |
| 配置类 RMW 是否被限定在 ISR 关断期 | 是（类型状态机 + 本文约定） |
| 命令类写寄存器是否被识别为原子 | 是（见第 2 节白名单） |
| ISR-safe 的 FFI 子集是否有清单 | 待补（`UNSAFE_AUDIT.md` 表 4 列"ISR-safe"） |
| 共享可变全局是否走原子 | 是（`AtomicU16` 约定，第 3 节） |
