# TI28035 ET JTAG 调试协议说明手册

本文档面向调试器开发，基于当前工程 RTL 与 UVM ET JTAG sequence 整理。

适用工程：

- RTL: `/scratch/home/wxu/work/s03_verify_git_merge/rtl/rtl/et/src`
- CPU debug FSM: `/scratch/home/wxu/work/s03_verify_git_merge/rtl/rtl/cpu/src/ET/CPU_ET.v`
- UVM ET JTAG: `/scratch/home/wxu/work/s03_verify_git_merge/verify/uvm_tb/env/mysubs/et_jtag`
- 仿真目录: `/scratch/home/wxu/work/s03_verify_git_merge/verify/uvm_sim`

当前结论来自 RTL 行为与仿真 sequence，不是公开 TI 工具协议的逐字摘录。开发 OpenOCD、Python JTAG driver 或 FPGA bring-up 调试器时，可以按本文档实现底层访问，再用仿真 case 对齐。

## 1. 总体模型

ET JTAG 通过 IEEE 1149.1 TAP 进入 ETAP/JTAP，再通过 38-bit IR 指令控制 ET。当前 RTL 中大多数 ET 操作都由 IR scan 触发，DR 主要用于普通 TAP 路径覆盖，例如 BYPASS/IDCODE/TESTMODE 的 DR shift。

主要模块分工：

| 模块 | 作用 |
|---|---|
| `ETAP/JTAP/JIR` | JTAG TAP、IR shift/update，产生 `JIR_PO`、`UpdateIR_UCK` |
| `CD.v` | command decode，译码 halt/run/step/reset/RT 等命令 |
| `RSAC.v/REQI.v/MD.v` | memory/debug access，把 READA/WRITEA/DATAB 变成访问请求 |
| `AD.v` | analysis/data-log/EMU_REG 总入口 |
| `EMU_REG.v` | DBGSTAT、ET_ST、AU、DMA、PSA、device/config register |
| `CPU_ET.v` | CPU RUN/HALT/STEP/RESET/ESTOP debug 状态机 |

调试器推荐启动流程：

```text
等待目标 boot 稳定
拉低 TRSTn，再释放
发送 BYPASS IR
发送 RT_DISABLE
可选：HALT_RUDE
读 DBGSTAT / ET_ST 确认状态
```

仿真中推荐等待 `4ms` 后开始 JTAG，是为了让 boot ROM 与测试 C 程序进入稳定循环。真实 FPGA/芯片上应改成等待 reset release、boot done 或用户配置的延时。

## 2. JTAG 物理信号

| 信号 | 说明 |
|---|---|
| `TRSTn` | TAP async reset，低有效 |
| `TCK` | JTAG clock |
| `TMS` | TAP state control |
| `TDI` | scan input |
| `TDO` | scan output |

JTAG bit shift 按标准 LSB-first。本文表中 `38'h3B_0000_80FF` 等数值按 RTL/SV 常量书写；实现 Python/OpenOCD driver 时，应把 bit0 先从 TDI 移入。

## 3. 基本事务

### 3.1 IR scan

UVM 封装：

```systemverilog
send_ir(ir_value[37:0], cnt_idle)
```

含义：

| 参数 | 含义 |
|---|---|
| `ir_value` | 38-bit ET/JTAG IR value |
| `cnt_idle` | Update-IR 后在 Run-Test/Idle 停留的 TCK 数 |

推荐 idle：

| 用途 | 建议 idle |
|---|---:|
| BYPASS / TAP sync | 3 |
| ET command | 10 |
| DATAB/READA/WRITEA | 10 |

### 3.2 DR scan

DR scan 不是 ET memory/register 的主要访问方式，主要用于 TAP 标准路径：

```systemverilog
send_dr(dr_value, bit_length, cnt_idle)
```

常见用途：

| IR | DR 长度 | 说明 |
|---|---:|---|
| BYPASS | 1 | bypass chain |
| IDCODE | 32 | ID code path |
| TESTMODE | 60 | testmode DR path |
| DC_STRBS | 32 | DC_STRBS path |

## 4. 38-bit IR 编码

### 4.1 Command 型完整 IR

| 名称 | IR value | RTL 信号/作用 |
|---|---:|---|
| BYPASS | `38'h3F_FFFF_FFFF` | TAP bypass |
| HALT_RUDE | `38'h3B_0000_80FF` | `Halt_Rude`，请求 CPU halt |
| HALT_POLITE | `38'h3B_0000_80DF` | `Halt_Polite`，polite halt |
| STEP_RUDE | `38'h3B_0000_81FF` | `Step_Rude`，单步 |
| STEP_POLITE | `38'h3B_0000_81DF` | `Step_Polite`，polite step |
| RUN_RUDE | `38'h3B_0000_86FF` | `Run_Rude`，从 debug halt 放行 |
| RUN_POLITE | `38'h3B_0000_86DF` | `Run_Polite` |
| FREE_RUN | `38'h3B_0000_87FF` | `FreeRun` |
| RT_ENABLE | `38'h3B_0000_00DF` | real-time mode enable |
| RT_DISABLE | `38'h3B_0000_00FF` | real-time mode disable |
| SET_RESET | `38'h3D_0000_0060` | 置 `set_reset_r` |
| RESET_STEP | `38'h3B_0000_85FF` | 若 `set_reset_r=1` 则 CPU reset；否则 nb_step |
| RT_ENABLE_ALT | `38'h3D_0000_0003` | alternate real-time enable |
| RT_DISABLE_ALT | `38'h3D_0000_0002` | alternate real-time disable |

### 4.2 Memory/Register 型 IR

这类指令格式为：

```text
IR[37:32] = opcode[5:0]
IR[31:0]  = address 或 data
```

| opcode | 名称 | IR[31:0] | 作用 |
|---:|---|---|---|
| `6'h31` | WRITEA16 | address | 把最近一次 DATAB 低 16bit 写到 address |
| `6'h32` | WRITEA32 | address | 把最近一次 DATAB 32bit 写到 address |
| `6'h33` | DATAB | data | 装载 write data |
| `6'h35` | READA16 | address | 读 16bit address |
| `6'h36` | READA32 | address | 读 32bit address |
| `6'h3C` | DMA_WDATA | data | data-log/DMA write data path |
| `6'h38` | DLOG_RCMD0 | don't care | data-log read command 0 |
| `6'h39` | DLOG_RCMD1 | don't care | data-log read command 1 |
| `6'h3A` | DLOG_RCMD2 | don't care | data-log read command 2，常用 FIFO pop |

普通 memory address 使用 32-bit 地址。EMU_REG 使用 22-bit 地址，放在低位：

```text
IR = {opcode, 10'h0, emureg_addr[21:0]}
```

## 5. CPU 控制 flow

### 5.1 HALT

命令：

```text
send_ir(HALT_RUDE, 10)
或 send_ir(HALT_POLITE, 10)
```

预期现象：

| 观测点 | 现象 |
|---|---|
| `CPU_W_Debug_Halt_State` | 变 1 |
| `CPU_W_Run_State` | 变 0 |
| PC | 停住 |
| `DBGSTAT[7:6]` | `2'b01`，表示 debug halt |

RTL 约束：`CPU_RUN` 状态下如果 `ET_W_CPU_Halt=1`，且不是 `ST1_DBGM && ET_W_Real_Time_Mode`，进入 `CPU_DEBUG_HALT`。

### 5.2 RUN

命令：

```text
send_ir(RUN_RUDE, 10)
或 send_ir(RUN_POLITE, 10)
```

预期现象：

| 观测点 | 现象 |
|---|---|
| `CPU_W_Run_State` | 变 1 |
| `CPU_W_Debug_Halt_State` | 变 0 |
| PC | 继续变化 |
| `DBGSTAT[7:6]` | run 时通常回到 `2'b00` |

注意：如果 RUN 后立即命中 ESTOP/HWBP/WP，可能几乎看不到 RUN 窗口，应按“发 RUN 后等待 halt/读 DBGSTAT”的方式处理，不要强制要求看到长时间 run。

### 5.3 STEP

命令：

```text
send_ir(STEP_RUDE, 10)
或 send_ir(STEP_POLITE, 10)
```

预期现象：

| 观测点 | 现象 |
|---|---|
| `CPU_W_Step_State` | 短暂为 1 |
| PC | 前进一条或一个可退休边界 |
| `CPU_W_Debug_Halt_State` | 单步完成后回 halt |

RTL 中 `CPU_STEP` 等待 `D1_W_Active` 与 `D2_To_W_Is_Flushed`。对 ESTOP 指令本身单步可能卡在 step state，不建议用“从 ESTOP0 step 到 ESTOP1”作为调试器流程。

### 5.4 RESET / nb_step / clr_step

流程：

```text
send_ir(SET_RESET, 10)
send_ir(RESET_STEP, 10)
```

作用：

| 条件 | `RESET_STEP` 效果 |
|---|---|
| `set_reset_r=1` | `CPU_Reset=1`，CPU 进入 debug halt |
| `set_reset_r=0` | `nb_step=1`，作为 non-breakable step |

`clr_step` 是 `RESET_STEP` opcode 的伴随清除动作。

### 5.5 polite / rude

RTL 中：

```text
ET_W_CPU_Polite = Step_Polite || Run_Polite || Halt_Polite
```

含义：

| 类型 | 说明 |
|---|---|
| rude | 立即型调试请求，适合验证与强制调试 |
| polite | 带 polite 标志，供分析/访存等逻辑判断是否采用更温和的请求方式 |

从当前 RTL 看，CPU 状态机的基本 RUN/HALT/STEP 进入条件主要看 `ET_W_CPU_Run/Step/Halt`，polite 额外进入 `ET_W_CPU_Polite`，影响 AD/MD/RSAC 等模块中的访问/事件策略。

## 6. Memory access

### 6.1 32-bit read

```text
IR = {READA32, address[31:0]}
send_ir(IR, 10)
等待 ack/data valid
```

在当前 UVM 中读目标 C 变量 `_a=0x00008D18`：

```systemverilog
send_ir({6'h36, 32'h0000_8D18}, 10);
```

### 6.2 32-bit write

```text
send_ir({DATAB, data[31:0]}, 10)
send_ir({WRITEA32, address[31:0]}, 10)
```

示例：

```text
write32(0x00008D18, 0x5A5A1234)
  send_ir({6'h33, 0x5A5A1234}, 10)
  send_ir({6'h32, 0x00008D18}, 10)
```

### 6.3 16-bit read/write

```text
read16(address):
  send_ir({6'h35, address}, 10)

write16(address, data16):
  send_ir({6'h33, 16'h0, data16}, 10)
  send_ir({6'h31, address}, 10)
```

注意：如果目标地址被 CPU 同时写，例如 C 程序 while-loop 中的 `_a++`，调试器读回值可能被 CPU 并发更新覆盖。严格 memory compare 应在 halt 后、或使用不会被 CPU 写的地址。

## 7. EMU_REG 直接 JTAG 访问

EMU_REG 地址是 22-bit。JTAG 访问时使用普通 READA/WRITEA opcode，但地址放入低 22bit：

```text
emureg_read32(addr22):
  send_ir({6'h36, 10'h0, addr22}, 10)

emureg_write32(addr22, data):
  send_ir({6'h33, data}, 10)
  send_ir({6'h32, 10'h0, addr22}, 10)

emureg_read16(addr22):
  send_ir({6'h35, 10'h0, addr22}, 10)

emureg_write16(addr22, data16):
  send_ir({6'h33, 16'h0, data16}, 10)
  send_ir({6'h31, 10'h0, addr22}, 10)
```

### 7.1 EMU_REG map

| 地址 | 名称 | JTAG 访问 | 说明 |
|---:|---|---|---|
| `0x800` | DBGSTAT low/full | R/W | debug status，写入会覆盖 `reg_800[14:0]` |
| `0x801` | DBGSTAT high16 | R | `{16'h0, reg_800[31:16]}` |
| `0x810` | ET_ST low | R | ET status low 32 |
| `0x811` | ET_ST low high16 | R | `reg_ET_ST_r[31:16]` |
| `0x812` | ET_ST high | R | `reg_ET_ST_r[63:32]` |
| `0x813` | ET_ST high high16 | R | `reg_ET_ST_r[63:48]` |
| `0x814` | debug bus | R | `{read_pending, ET_W_MC_Ren, ET_W_MC_Wen}` |
| `0x828` | AU0 mask low/full | R/W | 32-bit mask 或低 16bit |
| `0x829` | AU0 mask high16 | R/W16 | 高 16bit |
| `0x82A` | AU0 address low/full | R/W | breakpoint/watchpoint reference |
| `0x82B` | AU0 address high16 | R/W16 | 高 16bit |
| `0x82E` | AU0 control/id | R/W control | read32 返回 `{AU0_ID, AU0_CNTRL}`；write 写 control |
| `0x82F` | AU0 id | R | `{16'h0, AU0_ID}` |
| `0x830` | AU2 counter low/full | R/W | counter |
| `0x831` | AU2 counter high16 | R/W16 | 高 16bit |
| `0x832` | AU2 skip number low/full | R/W | skip number |
| `0x833` | AU2 skip number high16 | R/W16 | 高 16bit |
| `0x836` | AU2 control/id | R/W control | read32 返回 `{AU2_ID, AU2_CNTRL}` |
| `0x837` | AU2 id | R | `{16'h0, AU2_ID}` |
| `0x838` | DMA address low/full | R/W | DMA address |
| `0x839` | DMA address high16 | R/W16 | 高 16bit |
| `0x83A` | DMA read data | R | data-log/DMA read result |
| `0x83B` | DMA read data high16 | R | 高 16bit |
| `0x83C` | INT / data-log config | R/W | read 返回 `{reg_INT[31:11], ET_W_DLOGINT, reg_INT[9:6], fifo_cnt}` |
| `0x83E` | DMA control/id | R/W control | read32 返回 `{DMA_ID, DMA_CNTRL}` |
| `0x83F` | DMA id | R | `{16'h0, DMA_ID}` |
| `0x840` | PSA CRC/status | R/W via PSA | PSA_CRC40 window |
| `0x841` | PSA CRC high alias | R | high alias |
| `0x842` | PSA CRC/status | R/W via PSA | PSA_CRC40 window |
| `0x843` | PSA CRC/status | R/W via PSA | PSA_CRC40 window |
| `0x846` | PSA control/status | R/W via PSA | PSA enable/control window |
| `0x847` | PSA control high alias | R | high alias |
| `0x848` | AU1 mask low/full | R/W | 32-bit mask 或低 16bit |
| `0x849` | AU1 mask high16 | R/W16 | 高 16bit |
| `0x84A` | AU1 address low/full | R/W | reference address/data |
| `0x84B` | AU1 address high16 | R/W16 | 高 16bit |
| `0x84E` | AU1 control/id | R/W control | read32 返回 `{AU1_ID, AU1_CNTRL}` |
| `0x84F` | AU1 id | R | `{16'h0, AU1_ID}` |
| `0x880` | DEVICECNF low/full | R/W | device config，read 会拼接 TRST/XRS/VMAPS |
| `0x881` | DEVICECNF high16 | R/W16 | 高 16bit |
| `0x882` | CLASSID/REVID | R | `{12'h0, REVID, CLASSID}` |
| `0x883` | REVID | R | `{16'h0, 12'h0, REVID}` |
| `0x884` | PROTRANGE/PROTSTART | R/W | read32 `{PROTRANGE, PROTSTART}` |
| `0x885` | PROTRANGE | R/W16 | high half |
| `0x886` | SH_CLK_oe write / const read | W bit0, R const | write bit0 到 `SH_CLK_oe`，read 返回 `32'hEFFF_FFFF` |
| `0x887` | const | R | `32'h0000_EFFF` |
| `0x888` | const | R | `32'h0000_02EF` |
| `0x890` | reg_890 | R/W bits[2:1] | read `{29'h0, reg_890, 1'b1}` |
| `0x900` | device_id[31:0] | R | JTAG read；write 是 CPU/PF0-only |
| `0x901` | device_id[31:16] | R | high16 |
| `0x902` | device_id[63:32] | R | high 32 |
| `0x903` | device_id[63:48] | R | high16 |
| `0x904` | F2803X | R | `{29'h0, F2803X}`；write 是 CPU/PF0-only |
| `0x910` | branch_pc | R | `{10'h0, branch_pc}` |
| `0x982` | const | R | `32'hFFFF_FFFF` |
| `0x983` | const | R | `32'h0000_FFFF` |
| `0x984` | BOR_CFG high placement | R | `{15'h0, BOR_CFG, 16'h0}` |
| `0x985` | BOR_CFG low placement | R | `{16'h0, 13'h0, BOR_CFG}` |
| default | default decode | R | `32'h0` |

### 7.2 DBGSTAT bits

`DBGSTAT` 位来自 `reg_800`。常用位：

| bit | 名称 | 说明 |
|---:|---|---|
| 15 | IDLESTAT | idle status |
| 14 | HWBP | hardware breakpoint halt cause |
| 12 | WP | watchpoint halt cause |
| 11 | ESTOP1 | ESTOP1 halt cause |
| 10 | ESTOP0 | ESTOP0 halt cause |
| 7:6 | CPU state | `00` run，`01` debug halt |
| 4:0 | 常量/status | reset 后为 `5'h1F` |

写 DBGSTAT 的注意点：

```text
DBGSTAT_Wen 会写 reg_800[14:0]
CPU_ET.v 中 IRET_W_DBGSTAT_Wen 对 CPU_State 有额外影响
如果 CPU 已在 DEBUG_HALT，写 state[7:6]=00/10 不会直接放 RUN
真正从 halt 放行应使用 RUN_RUDE/RUN_POLITE
```

### 7.3 AU claim/control

AU/DMA 的 control/id 寄存器低两位用于 claim/enable/release 类动作。

| 写值低位 | 作用 |
|---:|---|
| `2'b01` | debugger claim |
| `2'b10` | enable |
| `2'b00` | release/disable |

调试器 claim 后 read32 control/id 可看到 ID：

| 资源 | control addr | DBG claim ID |
|---|---:|---:|
| AU0 | `0x82E` | `0x9001` |
| AU1 | `0x84E` | `0x9002` |
| AU2 | `0x836` | `0xA001` |
| DMA | `0x83E` | `0xB001` |

注意：RTL 中 `group1_DBG_Claim` 对 DMA 有一处写法使用了 `group1_DMA_CPU_Claim`，这可能影响某些 group1 互斥清除行为。调试器实现时建议每次只 claim 一个资源，用完 release。

### 7.4 DEVICECNF/PROT 副作用

`0x880/0x884/0x886/0x890` 可由 JTAG 直接写。调试器做 sweep 或诊断时应恢复默认值：

| 地址 | 建议恢复 |
|---:|---:|
| `0x880` | `0x080F_006B` |
| `0x884` | `0x00FF_0100` |
| `0x886` | 写 `0` 清 `SH_CLK_oe` |
| `0x890` | 写 `0x2`，使 read 为 `{..., reg_890=1, 1'b1}` |

## 8. 典型调试器 flow

### 8.1 连接并停止 CPU

```text
tap_reset()
ir(BYPASS)
ir(RT_DISABLE)
ir(HALT_RUDE)
dbgstat = emureg_read32(0x800)
assert dbgstat[7:6] == 2'b01
```

### 8.2 读 PC/status

```text
et_st0    = emureg_read32(0x810)
et_st1    = emureg_read32(0x812)
branch_pc = emureg_read32(0x910) & 0x003FFFFF
```

`branch_pc` 是 EMU_REG 捕获的分支/PC 观测值，调试器可用作 halt 后 PC 辅助信息。

### 8.3 单步 5 次

```text
for i in 0..4:
  ir(STEP_RUDE)
  wait_debug_halt()
  pc = emureg_read32(0x910)
```

### 8.4 memory read/write

```text
halt
old = read32(addr)
write32(addr, new_value)
check = read32(addr)
run
halt
```

### 8.5 hardware breakpoint AU0

```text
halt
emureg_write32(0x82E, 0x00000001)       # AU0 claim
emureg_write32(0x828, 0x00000000)       # exact mask
emureg_write32(0x82A, breakpoint_pc)    # reference PC
emureg_write32(0x82E, 0x0000042A)       # HWBP halt mode
run
wait_debug_halt
dbgstat = emureg_read32(0x800)
expect dbgstat[14] == 1
emureg_write32(0x82E, 0x00000000)       # release
```

### 8.6 ESTOP0 / ESTOP1

ESTOP 是 CPU 指令触发的 debug halt。RTL 在 D1 decode 中识别 ESTOP0/ESTOP1，且要求 `ET_W_EMU_Active=1`。

现象：

| 指令 | DBGSTAT bit |
|---|---:|
| ESTOP0 | `DBGSTAT[10]` |
| ESTOP1 | `DBGSTAT[11]` |

推荐调试器处理：

```text
run
wait_debug_halt
dbgstat = emureg_read32(0x800)
if dbgstat[10]: report ESTOP0
if dbgstat[11]: report ESTOP1
```

不要依赖“在 ESTOP0 halt 后 step 到下一条 ESTOP1”。当前 RTL/仿真看到这种 flow 可能卡在 `CPU_STEP`，更稳的做法是把 ESTOP0/ESTOP1 作为独立事件验证。

### 8.7 PSA/CRC data_valid

寄存器：

| 地址 | 说明 |
|---:|---|
| `0x840` | PSA seed/status high |
| `0x842` | PSA seed/status low |
| `0x843` | PSA alias |
| `0x846` | PSA control |

典型 flow：

```text
halt
emureg_write32(0x840, seed_hi)
emureg_write32(0x842, seed_lo)
emureg_write32(0x843, seed_alias)
emureg_write32(0x846, 0x12)       # enable
read32(memory_addr)               # 产生 RD_DATA_pulse / data_valid
read PSA registers
emureg_write32(0x846, 0x0)        # disable
```

### 8.8 DMA/data-log FIFO

关键寄存器：

| 地址 | 说明 |
|---:|---|
| `0x838/0x839` | DMA address |
| `0x83A/0x83B` | DMA read data |
| `0x83C` | INT/data-log command config，`reg_datlog_rcmd = reg_INT[21:16]` |
| `0x83E/0x83F` | DMA control/id |

JTAG 侧可 claim DMA：

```text
emureg_write32(0x83E, 0x00000001)   # debugger claim，ID 期望 0xB001
emureg_write32(0x838, addr)
emureg_write32(0x83C, 0x003A0000)   # rcmd = 6'h3A
send_ir({DLOG_RCMD2, 32'h0}, 10)    # FIFO pop/read command
data = emureg_read32(0x83A)
```

CPU/PF0 claim DMA 是另一条路径，ID 为 `0x7001`，需要 CPU 代码写 DEV_EMU window，JTAG 直接写不能覆盖 CPU-only claim 条件。

## 9. 调试器伪代码

### 9.1 IR scan helper

```python
def jtag_ir38(value, idle=10):
    bits = [(value >> i) & 1 for i in range(38)]  # LSB-first
    tap_shift_ir(bits)
    tap_idle(idle)
```

### 9.2 EMU_REG helpers

```python
OP_WRITEA16 = 0x31
OP_WRITEA32 = 0x32
OP_DATAB    = 0x33
OP_READA16  = 0x35
OP_READA32  = 0x36

def ir_op(op, payload):
    return ((op & 0x3f) << 32) | (payload & 0xffffffff)

def emu_addr(addr22):
    return addr22 & 0x003fffff

def emureg_read32(addr22):
    jtag_ir38(ir_op(OP_READA32, emu_addr(addr22)), idle=10)
    # RTL 当前路径主要通过内部 read_data/ack；真实 probe 需要按 TDO 数据路径实现 capture

def emureg_write32(addr22, data):
    jtag_ir38(ir_op(OP_DATAB, data), idle=10)
    jtag_ir38(ir_op(OP_WRITEA32, emu_addr(addr22)), idle=10)
```

当前 UVM sequence 用 backdoor 观察读写结果；真实硬件调试器需要把 RTL 中 REQI/ETAP 的 read data 返回到 TDO 的路径完整实现和校准。开发时建议先用仿真 co-sim 验证 IR scan 序列和状态变化，再接 FTDI/OpenOCD TDO 数据采样。

## 10. 当前验证 sequence 对应关系

| `+ET_JTAG_SEQ` | 作用 |
|---|---|
| `example` | boot 后 halt/run/step/memory/PC/AU0 示例 |
| `cmd_flow` | halt/run/step/free-run/RT enable disable |
| `reset_nbstep` | set_reset、CPU_Reset、nb_step、clr_step |
| `mem16_dbgstat` | READA16/WRITEA16 + DBGSTAT |
| `tap_dr_sweep` | BYPASS/IDCODE/TESTMODE/DC_STRBS/DR |
| `tap_pause` | TAP pause/exit2 state |
| `tap_reset` | TAP async TRST from multiple states |
| `emureg_sweep` | 常用 EMU_REG decode |
| `emureg_halfword` | 16-bit/high-half register decode |
| `emureg_direct` | JTAG 直接寄存器访问矩阵 |
| `psa_crc` | PSA register read |
| `psa_active` | PSA enable + memory read data_valid |
| `au_sweep` | AU0/AU1/AU2 claim/config |
| `au0_watchpoint` | AU0 HWBP/WP/RTOSINT modes |
| `au_watchpoint` | AU1 watchpoint/data/skip |
| `au2_counter` | AU2 counter/skip/event/DA |
| `dma_datalog` | JTAG DMA/data-log FIFO |
| `dma_cpu` | CPU/PF0 claimed DMA read |
| `rt_reset_corner` | RT alternate opcode/reset corner |
| `all_flow` | 综合 flow |
| `estop_wait` | ESTOP0 + DBGSTAT[10] |
| `estop1_wait` | ESTOP1 + DBGSTAT[11] |

单跑示例：

```bash
make --no-print-directory sim APP=et_jtag VERSION=28035 BOOT=emu_ram CPU=cpu WAVE=off EXTRA_SIMV_OPTS=+ET_JTAG_SEQ=emureg_direct
```

## 11. 开发注意事项

1. IR 长度必须是 38bit，且 LSB-first shift。
2. `DATAB` 必须在 `WRITEA16/WRITEA32` 前发送。
3. EMU_REG 地址要放在 32-bit payload 低 22bit，高 10bit 置 0。
4. 从 halt 放行必须用 RUN command，不要只写 DBGSTAT state 位。
5. ESTOP 后读 DBGSTAT 判断 cause；不要依赖 ESTOP 指令上单步越过。
6. `0x900~0x904` JTAG 可读，但写路径是 CPU/PF0-only。
7. `0x880/0x884/0x886/0x890` 有副作用，诊断访问后要恢复。
8. 如果目标 CPU 正在写同一 memory 地址，JTAG write/readback 可能被并发更新影响，应先 halt。
9. Polite/Rude 都能产生基本 run/halt/step 请求；polite 额外影响 ET 内部策略，基础调试器可先实现 rude。
10. 硬件 bring-up 时先验证 TAP BYPASS/IDCODE，再验证 BYPASS -> RT_DISABLE -> HALT -> DBGSTAT。

