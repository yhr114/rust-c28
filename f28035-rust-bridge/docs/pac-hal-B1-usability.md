# PAC/HAL 对表 C2000Ware 校准报告（第二轮，B-1 可用性结论）

日期：2026-10-27
依据：`platform/vendor/ti/f2803x/headers/include/DSP2803x_*.h`（寄存器文件与位域）
及 `platform/vendor/ti/f2803x/headers/cmd/DSP2803x_Headers_nonBIOS.cmd`（外设基地址 MEMORY 表）。
范围：`crates/c28x-pac/src/lib.rs`（纯 Rust PAC 全量 1414 行）+ `sdk/c-abi/f28035_bridge.c/h`（Safe HAL 的 FFI 真身）。

## 一、本轮新修复（源码已改，编译验证通过）

| # | 位置 | 错误 | 后果 | 修复 |
|---|---|---|---|---|
| 1 | c28x-pac `CpuTimer::clear_flag` | 写 TCR bit4 | bit4 是 **TSS**——清标志实际把定时器停了；TIF 在 **bit15**（w1c，TCR_BITS 表） | 改 `set_bits(1 << 15)` |
| 2 | c28x-pac `Sci::read_byte` | 轮询 SCIRXST bit0 | bit0 是**保留位**，RXRDY 在 **bit6**（SCIRXST_BITS 表）——串口永远读不到数据 | 改轮询 bit6 |
| 3 | c28x-pac `Sci::init` | SCICTL1 写 `(1<<5)\|(1<<4)\|(1<<3)` | bit4 保留、bit3 是 **TXWAKE**；TXENA(bit1)/RXENA(bit0) 根本没开——SCI 收发全 disabled | 改 `(1<<5)\|(1<<1)\|(1<<0)` |
| 4 | c28x-pac `Gpio` 幽灵寄存器 | 结构体含 `gpbqsel2`(0x6F94)、`gpbmux2`(0x6F98) | F2803x **不存在**这两个寄存器（GPIO_CTRL_REGS 中是 rsvd2/rsvd3 保留字） | 删除，替换为带注释的 rsvd 字段 |
| 5 | c28x-pac `Gpio` 位宽 | GPACTRL/GPADIR/GPAPUD/GPBCTRL/GPBDIR/GPBPUD 建模为 16 位 | TI 头文件中均为 **Uint32**；16 位写永远够不到 GPIO16-31 的方向/上拉 | 新增 `ProtectedReg32`，六个寄存器改 32 位建模 |
| 6 | 桥 `f28035_interrupts_enabled` | 返回 `IER & 1`（INT1 线使能位） | `CriticalSection::new()` 把它当**全局 INTM** 用——INT1 未路由时退出临界区不再开中断，CPU 全局锁死 | 改为影子变量跟踪任务级 INTM（ST1 不可作 cregister，只能软件跟踪；enable/disable 全部经桥收口，任务级精确） |
| 7 | 桥 `f28035_enable/disable_interrupts` | **只有 Rust FFI 声明，无任何 C 实现** | rust-api `CriticalSection` 一旦进 target 构建即链接失败 | 补 `CLRC/SETC INTM` 实现 + 影子更新 + 头文件声明 |
| 8 | 桥 `f28035_gpio_read_input`（上轮遗留） | `GpioCtrlRegs.GPADAT/GPBDAT` | **编译错误**（GPADAT/GPBDAT 在 GpioDataRegs 数据寄存器组）——上轮修改后从未编译过 | 改 `GpioDataRegs.*`；`build-c-bridge.ps1` 现 PASS，`nm2000` 确认三个中断符号均为 T |

## 二、逐外设对表结果（本轮核验，全部与 TI 头文件一致）

| 外设 | 基地址（cmd MEMORY 表） | 寄存器文件布局 | 位域 | 结论 |
|---|---|---|---|---|
| SysCtrl | 0x7010 | XCLK→WDCR 共 26 字全对齐 | WDCR=0x68（WDCHK=101+WDDIS）✓ | ✅ 可用 |
| CPU Timer0/1/2 | 0x0C00/0x0C08/0x0C10 | TIM/PRD/TCR/TPR/TPRH 对齐 | TSS=4/TRB=5/TIE=14 ✓；TIF=15（本轮修） | ✅ 修复后可用 |
| PIE | 0x0CE0 | PIECTRL/ACK/IER1-12/IFR1-12 对齐 | PIEACK w1c ✓ | ✅ 可用 |
| SPI A/B | 0x7040 / 0x7740 | 16 字布局含 FIFO 三寄存器全对齐 | SPISTS bit5 BUFFULL/bit6 INTFLAG ✓ | ✅ 可用 |
| SCI A | 0x7050 | 16 字布局对齐 | SCICCR/SCICTL1/SCICTL2 位域（本轮修 init/read_byte） | ✅ 修复后可用 |
| I2C | 0x7900 | OAR…PSC + rsvd[19] + FFTX/FFRX 对齐 | — | ✅ 可用（仅寄存器定义，无驱动逻辑） |
| ADC | 0x7100 / 结果 0x0B00 | 全 77 字对齐 | 上轮已修 ADCCTL1 电源位/SOCxCTL 字段/FLGCLR | ✅ 上轮修复后可用 |
| ePWM1-7 | 0x6800 步进 0x40 | **64 字逐一核对全对齐**（TBPHS/CMPA 联合体、TBPRDHR、TZDCSEL、镜像、DC 子组） | AQCTLA 上轮已修（ZRO=set/CAU=clear） | ✅ 上轮修复后可用 |
| eCAP1 | 0x6A00 | TSCTR…ECFRC 对齐 | — | ✅ 可用（仅定义） |
| eQEP1 | 0x6B00 | QPOSCNT…QCPRDLAT 全对齐 | — | ✅ 可用（仅定义） |
| GPIO 数据 | 0x6FC0 | GPADAT…GPBTOGGLE 8×32 位对齐 | GPBDAT 实为 Uint32 联合体 ✓ | ✅ 可用 |
| GPIO 控制 | 0x6F80 | 修复幽灵寄存器+位宽（本轮） | — | ✅ 修复后可用 |

## 三、B-1 可用性结论

- **可直接用于 B-1**（本轮对表+修复+编译验证后）：c28x-pac 全部 11 组外设定义、C 桥 GPIO/中断状态路径。
- **有硬件行为、但逻辑仍薄的**：SPI/SCI 的 PAC 侧只有阻塞读写+init；FIFO/中断模式只在 C 桥 case 里。寄存器定义本身无错。
- **仅定义、无驱动**：I2C、eCAP、eQEP 的 PAC 侧（地址/布局已验证正确）。
- **已知边界**：
  1. `f28035_interrupts_enabled` 现为影子语义——只反映任务级 INTM，ISR 内部瞬态不可见（CriticalSection 场景正确）。
  2. GPIOLPMSEL(0x6FD8)、AIODAT 组（0x6FD8+）未建模（无需求方，保持最小面）。
  3. 桥 GPIO pin 上限 44 为头文件宽裕边界，F28035 实际只有 GPIO0-34。
- **验证手段**：`tools/build-c-bridge.ps1` PASS（cl2000 eabi）；c28x-pac 以 active B-1 bundle rustc `cargo build --target c28x-none-elf --release` PASS；`nm2000` 确认 `f28035_enable/disable_interrupts`、`f28035_interrupts_enabled` 均为全局 T 符号。寄存器地址/位域逐条对 `DSP2803x_*.h` + `Headers_nonBIOS.cmd` 人工核对。
- **待真机回归**（下一步）：SCI 环回（验证 RXRDY bit6 与 SCICTL1 使能位）、Timer0 中断（验证 TIF bit15 清除）、PWM 占空比示波器复核（上轮 AQ/CMPA 修复）、`CriticalSection` 嵌套 RAM 样例。

## 三、B-1 真机验证（2026-10-27 第二轮新增，PASS）

真身 c28x-pac crate（active B-1 bundle rustc，c28x-none-elf 目标）经 TI cl2000
链接 RAM 映像，XDS100v1 + dss 读邮箱 0x9E00 判定。**8/8 全绿**：

| # | 邮箱 | 项 | 结果 |
|---|---|---|---|
| 0 | 0xC001 | 起始标记 | ✓ |
| 1 | 0x0004 | GPIO34 SET → GPBDAT 回读（32 位 GPBDIR + Reg32 数据组）| ✓ |
| 2 | 0x0000 | GPIO34 CLEAR → 回读 | ✓ |
| 3 | 0x8000 | **Timer0 TIF=TCR bit15 置位被观测**（校准点：旧实现误写 bit4=TSS）| ✓ |
| 4 | 0x0000 | **TIF w1c 清除 + TSS 停止**（= 桥 timer0_ack 0x8010 语义）| ✓ |
| 5 | 0x005A | **SCI 内部环回 RX==TX**（校准点：SCICTL1 TXENA/RXENA/SWRESET 使能位）| ✓ |
| 6 | 0x003C | SPI-B 内部环回 RX==TX（对齐桥 f28035_spi_internal_loopback_basic 实证序列）| ✓ |
| 7 | 0xC003 | 完成标记 | ✓ |

要点：
- 探针 crate：`crates/pac-hwtest-b1`（lib，依赖 c28x-pac 路径；panic_handler 内置）。
- 启动壳：`platform/runtime/pac_hwtest_ram_start.asm`（看门狗关闭后**保持 EALLOW**，
  与 c28x-pac 启动约定一致）+ `pac_hwtest_eallow.asm`（eallow_inst/edis_inst 叶函数，
  摘自 c28x-rt/asm.s——避免整链 c28x-rt 的 codestart 冲突）。
- 构建：`tools/build-pac-hwtest-b1-ram.ps1`（cargo rustc --lib --emit=obj × 2 +
  cl2000 链接；**两个 --emit=obj 对象**：探针 + c28x-pac 真身，bin 形态会被 GNU ld 拒绝）。
- 校验：`tools/verify-pac-hwtest-b1-ram.ps1`（dss 读邮箱精确比对 + image-stamp 门禁）。
- 真机校准结论落定：
  1. **TCR bit15=TIF（w1c）/ bit4=TSS** —— 校准正确，旧 clear_flag 会在真机上停掉定时器；
  2. **SCICTL1 bit0=RXENA / bit1=TXENA / bit5=SWRESET** —— 校准前收发全断（写到了保留位+TXWAKE）；
  3. **SCI FIFO 路径 RXFFST/RXBUF 正常**；RXRDY 非 FIFO 位为 bit6（SCIRXST），bit0 为保留（校准正确）；
  4. **外设时钟门**：PCLKCR0 复位全关 —— SCI-A(bit10)/SPI-A(bit8)/SPI-B(bit9) 必须显式开启，
     Timer0/GPIO 不经门控（这解释了为何旧代码"看似能用"：走 C 桥时 InitSysCtrl 已代开）。
  5. SPI-B 环回需 SPIBENCLK(bit9)——本探针曾因此失败一次；SPI-A 环回与 SPI-B 配置差异
     （CLK_PHASE=0x000E vs 0x0006）亦可能相关，按桥实证序列走 SPI-B 为准。

## 四、最终结论（更新）

- **PAC/HAL 可直接用于 B-1：是**（本轮真机验证后）。统一寄存器实现 =
  c28x-pac（Rust 真身）与 C 桥（TI 头文件）双路对表 DSP2803x_*.h，
  关键行为经 XDS100v1 真机复核（GPIO/Timer0/SCI/SPI）。
- 真机回归工具链：`tools/verify-pac-hwtest-b1-ram.ps1`（一键重建+上板）。
