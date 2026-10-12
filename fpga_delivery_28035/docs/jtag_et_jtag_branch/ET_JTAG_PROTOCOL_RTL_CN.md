# ET JTAG RTL 协议与验证现象说明

本文档基于当前 RTL 与 UVM ET JTAG subenv 整理，目标是给验证用例、checker、覆盖率分析提供统一参考。

工程路径：

- RTL: `/scratch/home/wxu/work/s03_verify_git_merge/rtl/rtl/et/src`
- CPU debug RTL: `/scratch/home/wxu/work/s03_verify_git_merge/rtl/rtl/cpu/src/ET/CPU_ET.v`
- UVM ET JTAG: `/scratch/home/wxu/work/s03_verify_git_merge/verify/uvm_tb/env/mysubs/et_jtag`
- 仿真目录: `/scratch/home/wxu/work/s03_verify_git_merge/verify/uvm_sim`

## 1. RTL 模块分工

| 模块 | 主要职责 |
|---|---|
| `ET.v` | ET 顶层，连接 ETAP/CD/AD/MD/mem mux 与 CPU debug 信号 |
| `ETAP/JTAP/JIR` | JTAG TAP 与 IR shift/update 路径，产生 `JIR_PO`、`UpdateIR_UCK` |
| `CD.v` | Command Decode，译码 halt/run/step/reset/RT mode 等 38-bit command |
| `MD.v` | Memory Debug 访问顶层，连接 RSAC 与 REQI |
| `RSAC.v` | 译码 `READA/WRITEA/DATAB`，生成 memory/emureg 访问 |
| `REQI.v` | 把 RSAC read/write 请求转成 `ETAP_mem_*` 访问 |
| `AD.v` | Analysis/Data log/EMU_REG 总入口，生成 breakpoint/watchpoint/data logging 相关事件 |
| `EMU_REG.v` | ET emulation 寄存器读写、DBGSTAT/ET_ST/AU/DMA register 实现 |
| `CPU_ET.v` | CPU debug 状态机，实现 RUN/HALT/STEP/RESET/ESTOP 对 CPU 状态的影响 |

## 2. JTAG 事务模型

当前 UVM 用 Synopsys SVT JTAG VIP 驱动，封装在 `et_jtag_basic_sequence.sv`：

```systemverilog
virtual task send_ir(input bit [37:0] ir_value, input int cnt_idle = 3);
    tx_xact.cmd_type       = svt_jtag_types::IR;
    tx_xact.enable_cmd_tdi = 1'b1;
    tx_xact.cmd_ir_tdi    = ir_value;
    tx_xact.cnt_idle      = cnt_idle;
endtask
```

`send_ir(value, cnt_idle)` 参数含义：

| 参数 | 含义 |
|---|---|
| `ir_value[37:0]` | Shift 到 JTAG IR 链的 38-bit 指令/命令 |
| `cnt_idle` | Update-IR 后停留 Run-Test/Idle 的 TCK cycle 数 |

当前 ET 指令都通过 IR scan 发出。`READA/WRITEA/DATAB` 也是 IR 指令，不是单独 DR 指令。

常用 idle 建议：

| 用途 | 建议 `cnt_idle` |
|---|---:|
| BYPASS/link wakeup | `3` |
| ET 控制命令 | `10` |
| memory/emureg read/write | `10` |

## 3. Pad 与启动时序

ET JTAG subenv 通过 `et_jtag_if` 接管 JTAG pad：

| Pad | JTAG 作用 |
|---|---|
| `TRSTn` | JTAG reset / JTAG mode select |
| `GPIO38orXCLKINorTCK` | TCK |
| `GPIO36orTMS` | TMS |
| `GPIO35orTDI` | TDI |
| `GPIO37orTDO` | TDO |

推荐 sequence 起始流程：

```text
#4ms
TRST reset
BYPASS
RT_DISABLE
```

原因：

- `#4ms` 让 boot ROM/C 程序先跑起来。
- TRST reset 保证 TAP/JIR 初始状态干净。
- BYPASS 是 harmless transaction，用于让 JTAP/ET active 先稳定。
- `RT_DISABLE` 避免 real-time mode + DBGM 导致 halt/step 不真正停住。

## 4. 38-bit Command Decode

RTL 依据：`CD.v`

| Flow | 38-bit IR | RTL 译码信号 | 预期现象 |
|---|---:|---|---|
| BYPASS | `38'h3F_FFFF_FFFF` | BYPASS IR | 不影响 CPU，只确认 JTAG path |
| RT_ENABLE | `38'h3B_0000_00DF` | `RT_mode_enable` | `ET_W_Real_Time_Mode=1` |
| RT_DISABLE | `38'h3B_0000_00FF` | `RT_mode_disable` | `ET_W_Real_Time_Mode=0` |
| RT_ENABLE alt | `38'h3D_0000_0003` | `RT_mode_enable` | 同 RT_ENABLE |
| RT_DISABLE alt | `38'h3D_0000_0002` | `RT_mode_disable` | 同 RT_DISABLE |
| HALT_RUDE | `38'h3B_0000_80FF` | `Halt_Rude` | CPU 进入 debug halt |
| HALT_POLITE | `38'h3B_0000_80DF` | `Halt_Polite` | 当前 RTL 中对 CPU 效果同 HALT_RUDE |
| RUN_RUDE | `38'h3B_0000_86FF` | `Run_Rude` | CPU 从 halt 进入 run |
| RUN_POLITE | `38'h3B_0000_86DF` | `Run_Polite` | 当前 RTL 中对 CPU 效果同 RUN_RUDE |
| STEP_RUDE | `38'h3B_0000_81FF` | `Step_Rude` | 单步一条有效指令后回 halt |
| STEP_POLITE | `38'h3B_0000_81DF` | `Step_Polite` | 当前 RTL 中对 CPU 效果同 STEP_RUDE |
| FREE_RUN | `38'h3B_0000_87FF` | `FreeRun` | 当前 RTL 中并入 `ET_W_CPU_Run`，现象同 RUN |
| SET_RESET | `38'h3D_0000_0060` | `set_reset` | 置 `set_reset_r=1`，本身不 reset CPU |
| RESET/85FF | `38'h3B_0000_85FF` | `CPU_Reset` 或 `nb_step`，同时 `clr_step` | 取决于 `set_reset_r` |

`CD.v` 中组合关系：

```verilog
ET_W_CPU_Halt = Halt_Rude || Halt_Polite || AD_Halt;
ET_W_CPU_Run  = Run_Rude || Run_Polite || FreeRun || HWBP_run;
ET_W_CPU_Step = Step_Rude || Step_Polite || nb_step;
ET_W_CPU_Polite = Step_Polite || Run_Polite || Halt_Polite;
```

注意：`ET_W_CPU_Polite` 在当前 CPU 控制路径中没有改变 CPU 状态机行为，因此 halt/run/step 的 polite/rude 主要是 opcode decode 覆盖点，现象基本一致。

## 5. CPU Debug 状态机现象

RTL 依据：`CPU_ET.v`

CPU debug 状态：

| 状态 | RTL 表示 | 现象 |
|---|---|---|
| RUN | `CPU_RUN` / `CPU_W_Run_State=1` | PC 持续变化 |
| DEBUG_HALT | `CPU_DEBUG_HALT` / `CPU_W_Debug_Halt_State=1` | PC 保持，debug 可观察 |
| STEP | `CPU_STEP` / `CPU_W_Step_State=1` | 执行一条有效指令后回 halt |
| XINT_SAVE_CONTEXT | `CPU_XINT_SAVE_CONTEXT` | real-time interrupt 相关 |

### 5.1 Halt flow

输入：

```text
send_ir(ET_JTAG_CMD_HALT_RUDE, 10)
或 send_ir(ET_JTAG_CMD_HALT_POLITE, 10)
```

RTL：

```verilog
if (ET_W_CPU_Halt) begin
    if (ST1_DBGM && ET_W_Real_Time_Mode)
        CPU_State_Next = CPU_RUN;
    else
        CPU_State_Next = CPU_DEBUG_HALT;
end
```

预期现象：

| 条件 | 现象 |
|---|---|
| `ET_W_Real_Time_Mode=0` | CPU 进入 `CPU_DEBUG_HALT`，PC hold |
| `ET_W_Real_Time_Mode=1 && ST1_DBGM=1` | halt request 可能被忽略，CPU 继续 run |
| 已经 halt | 继续保持 halt |

验证 checker：

- `cpu_debug_halt == 1`
- `cpu_run == 0`
- PC 在后续若干 clock 不变化
- `DBGSTAT[7:6] == 2'b01`

### 5.2 Run flow

输入：

```text
send_ir(ET_JTAG_CMD_RUN_RUDE, 10)
send_ir(ET_JTAG_CMD_RUN_POLITE, 10)
send_ir(ET_JTAG_CMD_FREE_RUN, 10)
```

预期现象：

- CPU 从 `DEBUG_HALT` 进入 `RUN`
- `cpu_run == 1`
- `cpu_debug_halt == 0`
- PC 开始变化
- `DBGSTAT[7:6] == 2'b00`

### 5.3 Step flow

输入：

```text
send_ir(ET_JTAG_CMD_STEP_RUDE, 10)
send_ir(ET_JTAG_CMD_STEP_POLITE, 10)
send_ir(ET_JTAG_CMD_RESET_STEP, 10) // no prior set_reset 时作为 nb_step
```

RTL 行为：

- 从 halt 进入 `CPU_STEP`
- 等有效指令进入 pipeline
- 等 `D2_To_W_Is_Flushed`
- 若不是 real-time DBGM 阻挡，则回 `CPU_DEBUG_HALT`

预期现象：

- step 期间 `cpu_step` 可能短暂为 1
- 完成后 `cpu_debug_halt == 1`
- PC 前进或跳转一次
- 分支/循环场景下 PC 变化可能不是简单 +1

### 5.4 Reset / nb_step / clr_step

`38'h3B_0000_85FF` 是复用命令：

| 前置条件 | RTL 行为 | 现象 |
|---|---|---|
| `set_reset_r=0` | `nb_step=1` | 等价 step |
| `set_reset_r=1` | `CPU_Reset=1` | 产生 `ET_W_CPU_Reset`，CPU 进 debug halt |
| 任意 | `clr_step=1` | 清 `set_reset_r` |

CPU reset flow：

```text
send_ir(38'h3D_0000_0060, 10) // SET_RESET
send_ir(38'h3B_0000_85FF, 10) // CPU_Reset + clr_step
```

预期现象：

- `ET_W_CPU_Reset` pulse
- `CPU_State <= CPU_DEBUG_HALT`
- `Inst_Count <= 0`

## 6. Real-time mode 与 DBGM

`ET_W_Real_Time_Mode` reset 后默认为 1。

| 命令 | 作用 |
|---|---|
| `RT_ENABLE` | 置 `ET_W_Real_Time_Mode=1` |
| `RT_DISABLE` | 置 `ET_W_Real_Time_Mode=0` |

关键规则：

```text
real-time mode + ST1.DBGM=1 时，halt/hardware breakpoint 可能不让 CPU 停住
```

验证建议：

1. 普通 halt/run/step 前先发 `RT_DISABLE`。
2. 专门做 real-time case 时，设置 `ST1.DBGM=1` 后发 halt/step，预期 CPU 可能继续 run。
3. 读 `ET_ST0` 中 `DBGM` 与 `ET_W_Real_Time_Mode` 镜像位辅助判断。

## 7. Memory / EMUREG 访问格式

RTL 依据：`RSAC.v`

IR 字段格式：

```text
READ/WRITE/DATAB IR = {op[5:0], payload[31:0]}
```

| Flow | op[5:0] | IR payload | RTL 信号 | 作用 |
|---|---:|---|---|---|
| WRITEA16 | `6'h31` | address[31:0] | `WriteA16` | 16-bit write |
| WRITEA32 | `6'h32` | address[31:0] | `WriteA32` | 32-bit write |
| DATAB | `6'h33` | data[31:0] | `DataB` | 装载写数据 |
| READA16 | `6'h35` | address[31:0] | `ReadA16` | 16-bit read |
| READA32 | `6'h36` | address[31:0] | `ReadA32` | 32-bit read |

地址译码：

| 访问类型 | RTL 条件 | 地址 |
|---|---|---|
| EMUREG | `RSAC_IR[21:8] == 14'h8` 或 `14'h9` | `{1'b0, RSAC_IR[21:0]}` |
| CPU core reg | `RSAC_IR[31:24] == 8'h7A/3A/12` | `{1'b1, 16'h0, cpu_addr}` |
| memory/peripheral | 默认 | `{1'b0, RSAC_IR[21:0]}` |

写流程：

```text
send_ir({6'h33, data}, 10)      // DATAB
send_ir({6'h32, address}, 10)   // WRITEA32
```

读流程：

```text
send_ir({6'h36, address}, 10)   // READA32
```

当前 UVM 读值注意：

- 现有 helper 会发 READA，但数据比对主要通过 backdoor observe。
- 若要严格验证 TDO readback，需要打开 SVT response：`enable_get_response=1`，并用 `get_response(rsp)` 读取 sampled TDO。

## 8. EMUREG 地址表

RTL 依据：`EMU_REG.v`

常用地址：

| 地址 | 名称/用途 | R/W | 当前验证状态 |
|---:|---|---|---|
| `0x800` | `DBGSTAT` | R/W via CPU debug context / R | 已有 helper，`all_flow` 读取 |
| `0x810` | `ET_ST0` low/status | R | 已读 |
| `0x828` | AU0 address mask low/full | R/W | AU0 HWBP 使用 |
| `0x829` | AU0 mask high 16-bit | W | 未单独覆盖 |
| `0x82A` | AU0 address low/full | R/W | AU0 HWBP 使用 |
| `0x82B` | AU0 address high 16-bit | W | 未单独覆盖 |
| `0x82E` | AU0 control / ID | R/W | AU0 claim/enable/disable 使用 |
| `0x848` | AU1 address mask | R/W | 未覆盖 |
| `0x84A` | AU1 address | R/W | 未覆盖 |
| `0x84E` | AU1 control / ID | R/W | 未覆盖 |
| `0x832` | AU2 skip number | R/W | 未覆盖 |
| `0x836` | AU2 control | R/W | 未覆盖 |
| `0x838` | data log address/current addr | R | 未覆盖 |
| `0x83A` | DMA read data | R | 未覆盖 |
| `0x83C` | INT / DLOGINT / fifo count | R/W | 未覆盖 |
| `0x83E` | `{DMA_ID, DMA_CNTRL}` | R/W low control | 未覆盖 |
| `0x83F` | `DMA_ID` | R | 未覆盖 |
| `0x880` | DEVICECNF/status | R | 未覆盖 |
| `0x884` | PROT range/start | R | 未覆盖 |
| `0x900-0x903` | device id | R | 未覆盖 |
| `0x904` | F2803X id | R | 未覆盖 |
| `0x910` | `branch_pc` | R | 已读 |
| `0x984/0x985` | BOR config | R/W | 未覆盖 |

## 9. DBGSTAT 关键位

RTL 依据：`EMU_REG.v reg_800`

| Bit | RTL 更新 | 含义/现象 |
|---:|---|---|
| `[15]` | `IDLESTAT` | CPU idle 状态 |
| `[14]` | `HWBP_Halt` 相关 | hardware breakpoint halt 原因 |
| `[13]` | 当前置 0 | 保留/未用 |
| `[12]` | `WP_Halt` 相关 | watchpoint halt 原因 |
| `[11]` | `CPU_W_ESTOP1` | ESTOP1 halt 原因 |
| `[10]` | `CPU_W_ESTOP0` | ESTOP0 halt 原因 |
| `[9]` | 当前置 0 | 保留/未用 |
| `[8]` | 当前置 0 | 保留/未用 |
| `[7:6]` | run/halt 状态 | RUN 时 `00`，非 RUN 时 `01` |
| `[5]` | 当前置 0 | 保留/未用 |
| `[4:0]` | 默认 `5'h1F` | 状态默认位 |

检查建议：

| Flow | 期望 DBGSTAT |
|---|---|
| RUN | `[7:6]=00` |
| HALT/STEP 后 halt | `[7:6]=01` |
| AU0 HWBP halt | `[14]=1` |
| Watchpoint halt | `[12]=1` |
| ESTOP1 | `[11]=1` |
| ESTOP0 | `[10]=1` |

## 10. ET_ST0 关键位

RTL 依据：`EMU_REG.v reg_ET_ST_r`

常用观察位：

| Bit | 含义 |
|---:|---|
| `[61:40]` | IC / ET status PC 镜像 |
| `[34]` | `ET_W_Real_Time_Mode` |
| `[33]` | ET halt/status 镜像 |
| `[32]` | `IDLESTAT` |
| `[26]` | run/halt 相关状态 |
| `[25]` | run 相关状态 |
| `[22]` | `INTM` |
| `[20]` | `DBGM` |
| `[12]` | reset pending |

## 11. ESTOP0 / ESTOP1

CPU fetch D1 阶段识别：

| 指令 | opcode | RTL 信号 | TI 语义 | 现象 |
|---|---:|---|---|---|
| ESTOP0 | `16'h7625` | `CPU_W_ESTOP0` | software breakpoint，PC 不增加 | CPU halt，`DBGSTAT[10]=1` |
| ESTOP1 | `16'h7624` | `CPU_W_ESTOP1` | embedded breakpoint，PC 指向下一条 | CPU halt，`DBGSTAT[11]=1` |

ESTOP flush：

```verilog
ET_W_Flush_st <= CPU_W_ESTOP0 || CPU_W_ESTOP1;
ET_W_Flush_Fetch_Pipeline =
    ((ET_W_CPU_Run || ET_W_CPU_Step) && ET_W_Flush_st) ||
    (ET_W_CPU_Step && CPU_W_Step_State);
```

作用：

- ESTOP halt 后，下一次 run/step 产生 fetch pipeline flush。
- 避免旧 ESTOP 残留导致恢复后马上再次停住。

## 12. AU0 Hardware Breakpoint

当前已验证 AU0 exact PC breakpoint。

配置流程：

```text
WRITE 0x82E = 0x0000_0001   // claim AU0
WRITE 0x828 = 0x0000_0000   // exact match mask
WRITE 0x82A = bp_pc         // breakpoint PC
WRITE 0x82E = 0x0000_042A   // enable HWBP halt
RUN_RUDE
wait CPU debug halt
READ DBGSTAT/ET_ST0/AU0
WRITE 0x82E = 0             // disable
```

预期现象：

- CPU run 到匹配 PC 附近后进入 debug halt。
- `DBGSTAT[14]=1`。
- `branch_pc/ET_ST0 PC` 可用于判断停止点。

当前 C case `_a++` 循环中常用 breakpoint 地址：

```text
_main loop:
0x85e0 MOVB ACC,#1
0x85e3 ADDL @0x18,ACC
0x85e5 SB -5,UNC

AU0 breakpoint = 0x85e3
```

## 13. Watchpoint / Data Logging 状态

RTL 有相关资源，但当前 UVM sequence 仍是 placeholder：

| Flow | RTL 支持方向 | 当前验证状态 |
|---|---|---|
| Watchpoint read | AU address/data compare -> `WP_Halt` | task 已定义，控制值待确认 |
| Watchpoint write | AU address/data compare -> `WP_Halt` | task 已定义，控制值待确认 |
| Data logging | `DMA_CNTRL/EVT_CNTRL/INT/DLOGINT` | task 已定义，具体流程待实现 |

实现这些 flow 前需要先确认 AU control bit 编码，避免假覆盖。

## 14. Polite / Rude 说明

TI C28x 手册中 polite/rude 主要用于 DT-DMA/debug access：

| 类型 | `DBGM=0` | `DBGM=1` |
|---|---|---|
| polite | 允许 | 等待/被挡 |
| rude | 允许 | 仍允许 |

当前 RTL：

- halt/run/step 有 polite/rude opcode。
- `CD.v` 译码出 `ET_W_CPU_Polite`。
- 但 CPU 状态机没有因 `ET_W_CPU_Polite` 改变 halt/run/step 行为。
- data logging/memory 侧有 `reg_DMA_CNTRL[9]`、`reg_DMA_CNTRL[14]` 等 polite/prioriy 相关位。

验证结论：

- `HALT_POLITE` 与 `HALT_RUDE` 现象目前应基本一致。
- 真正的 polite/rude 差异应以后在 `DBGM=1` 的 memory/DT-DMA access case 中验证。

## 15. 当前 UVM Sequence

默认 sequence：

| Seq | plusarg | 覆盖 |
|---|---|---|
| `et_jtag_example_sequence` | 默认或 `+ET_JTAG_SEQ=example` | 原 smoke: RT_DISABLE, halt/run/step, memory32, AU0 HWBP |
| `et_jtag_cmd_flow_sequence` | `+ET_JTAG_SEQ=cmd_flow` | polite/rude halt/run/step, FreeRun, RT enable/disable |
| `et_jtag_reset_nbstep_sequence` | `+ET_JTAG_SEQ=reset_nbstep` | nb_step, set_reset, CPU_Reset |
| `et_jtag_mem16_dbgstat_sequence` | `+ET_JTAG_SEQ=mem16_dbgstat` | READA16, WRITEA16, DBGSTAT |
| `et_jtag_estop_wait_sequence` | `+ET_JTAG_SEQ=estop_wait` | 等 ESTOP C image |
| `et_jtag_all_flow_sequence` | `+ET_JTAG_SEQ=all_flow` | 串联大部分安全 flow |

`all_flow` 顺序：

```text
prepare
halt_rude
run_rude
halt_polite
run_polite
halt_rude
step_rude
step_polite
nb_step
clr_step
cpu_reset
read_dbgstat
read_et_st0
read_pc
reada32
datab
writea32
reada16
writea16
run_rude
halt_rude
free_run
halt_rude
rt_enable
rt_disable
hw_breakpoint_au0
watchpoint_read placeholder
watchpoint_write placeholder
data_logging placeholder
optional estop_wait
```

运行示例：

```bash
cd /scratch/home/wxu/work/s03_verify_git_merge/verify/uvm_sim

make run TB_ET_JTAG=1 EXTRA_SIMV_OPTS=+ET_JTAG_SEQ=cmd_flow
make run TB_ET_JTAG=1 EXTRA_SIMV_OPTS=+ET_JTAG_SEQ=reset_nbstep
make run TB_ET_JTAG=1 EXTRA_SIMV_OPTS=+ET_JTAG_SEQ=mem16_dbgstat
make run TB_ET_JTAG=1 EXTRA_SIMV_OPTS=+ET_JTAG_SEQ=all_flow
```

ESTOP 需要专门 C image：

```bash
make run TB_ET_JTAG=1 EXTRA_SIMV_OPTS="+ET_JTAG_SEQ=all_flow +ET_JTAG_RUN_ESTOP_FLOW"
```

## 16. 推荐 checker 信号

| 信号 | 作用 |
|---|---|
| `ET_W_Real_Time_Mode` | RT_ENABLE/DISABLE 结果 |
| `ET_W_CPU_Halt` | halt command pulse |
| `ET_W_CPU_Run` | run/free-run command pulse |
| `ET_W_CPU_Step` | step/nb_step command pulse |
| `ET_W_CPU_Reset` | CPU reset command pulse |
| `CPU_W_Run_State` | CPU run 状态 |
| `CPU_W_Debug_Halt_State` | CPU halt 状态 |
| `CPU_W_Step_State` | CPU step 状态 |
| `ET_W_Flush_Fetch_Pipeline` | ESTOP/step flush |
| `ST1_DBGM` | real-time debug mask |
| `DBGSTAT[14]` | HWBP halt |
| `DBGSTAT[12]` | watchpoint halt |
| `DBGSTAT[11]` | ESTOP1 |
| `DBGSTAT[10]` | ESTOP0 |
| `DBGSTAT[7:6]` | run/halt 状态 |
| `PC/branch_pc/ET_ST0[61:40]` | PC 停止/前进/断点位置 |

## 17. 已知限制与后续补充

| 项目 | 当前状态 | 后续建议 |
|---|---|---|
| TDO readback | 多数 read 用 backdoor observe | 引入 SVT `get_response` 做 TDO compare |
| polite/rude memory DBGM | 未完整验证 | 写 DBGM=1 case，区分 polite/rude |
| Watchpoint | placeholder | 确认 AU control encoding 后实现 |
| Data logging | placeholder | 按 `DMA_CNTRL/EVT_CNTRL` claim/enable/complete 实现 |
| AU1/AU2 | 未覆盖 | 补 AU1 breakpoint/watchpoint，AU2 counter/skip |
| ESTOP C image | 需要专门软件 | 编译 ESTOP0/ESTOP1 case 后跑 `estop_wait` |

## 18. 与 TI 手册一致性评估

参考文档：

- `C:\Users\Admin\Desktop\28035\doc\spru430f.pdf`: TMS320C28x CPU and Instruction Set Reference Guide，第 7 章 Emulation Features。
- `C:\Users\Admin\Desktop\28035\doc\sprui10a.pdf`: TMS320F2803x TRM，JTAG pin、TRST boot、CSM/ECSL、外设 emulation 行为。

### 18.1 总体结论

当前 RTL 与 TI C28x emulation 架构在主功能上基本一致：

- 支持 JTAG debug access。
- 支持 debug halt/run/single-step 三类 CPU debug 执行状态。
- 支持 real-time mode，并体现 `DBGM` 对 halt/debug event 的影响。
- 支持 DT-DMA 风格 memory/register/emureg 访问。
- 支持 ESTOP0/ESTOP1 software breakpoint。
- 支持 analysis breakpoint/watchpoint/data logging 资源框架。

但也有几处需要验证中特别标注：

- 38-bit ET JTAG command opcode 是当前 RTL 私有实现，TI 公开手册没有列这些 opcode。
- `HALT/RUN/STEP` 的 polite/rude 在当前 RTL 中对 CPU 状态机效果基本一致。
- `FREE_RUN` 当前 RTL 仅并入 `ET_W_CPU_Run`，没有看到比普通 run 更多的 CPU 行为。
- watchpoint/data logging 资源在 RTL 中存在，但当前 UVM flow 还没有完整验证。

### 18.2 高一致性项目

| 项目 | TI 手册语义 | 当前 RTL 实现 | 评估 |
|---|---|---|---|
| JTAG debug interface | C28x emulation 通过 JTAG 与 TI extension 支持 debug | ETAP/JTAP/JIR 接收 JTAG IR，UVM SVT JTAG 驱动 TCK/TMS/TDI/TRST | 一致 |
| TRST/JTAG mode | F28035 TRM 描述 TRST/JTAG pin 复用与 emulation boot | TB 中 ET JTAG 接管 TRST/TCK/TMS/TDI/TDO pad | 一致 |
| Debug halt state | break event 或 host request 可进入 debug-halt | `ET_W_CPU_Halt` 使 `CPU_State` 进入 `CPU_DEBUG_HALT` | 一致 |
| Run state | debugger run command 让 CPU 执行程序 | `ET_W_CPU_Run` 使 `CPU_DEBUG_HALT -> CPU_RUN` | 一致 |
| Single-step | 执行一条指令后回 debug-halt | `ET_W_CPU_Step -> CPU_STEP`，等 `D2_To_W_Is_Flushed` 后回 halt | 一致 |
| Real-time mode | halt 时可服务 time-critical interrupt，`DBGM` 会影响 debug event | `ST1_DBGM && ET_W_Real_Time_Mode` 时 halt/step 后继续 run | 高一致 |
| DT-DMA access | debug host 可在 pipeline hole/forced hole 访问 memory/register | `READA/WRITEA/DATAB` 经 RSAC/REQI 访问 memory/emureg | 架构一致 |
| ESTOP0 | opcode `16'h7625`，software breakpoint，PC 不增加 | D1 识别 `16'h7625` 产生 `CPU_W_ESTOP0` | 完全一致 |
| ESTOP1 | opcode `16'h7624`，embedded breakpoint，PC 指向下一条 | D1 识别 `16'h7624` 产生 `CPU_W_ESTOP1` | 完全一致 |
| Analysis breakpoint | instruction 进入 D2 前由 bus comparator 触发 halt | AU0/AU1 地址/掩码/控制寄存器触发 `HWBP_Halt/AD_Halt` | 一致 |
| DBGSTAT | debug status register 保存 debug 状态/原因 | `reg_800` 保存 run/halt、HWBP、WP、ESTOP 原因位 | 一致方向 |

### 18.3 部分一致或当前 RTL 简化项目

| 项目 | TI 手册期望 | 当前 RTL 现象 | 风险/说明 |
|---|---|---|---|
| Command opcode | TI 手册描述 debugger command 语义，不公开具体 38-bit opcode | RTL 使用 `38'h3B_...` / `38'h3D_...` 私有 opcode | 验证以 RTL opcode 为准，文档需注明非公开 TI opcode |
| `HALT_POLITE/RUDE` | polite/rude 主要用于 DT-DMA access，rude 可忽略 `DBGM` | CD 译码出 polite/rude，但 CPU 状态机只看 `ET_W_CPU_Halt` | 当前二者 halt 现象基本一致 |
| `RUN_POLITE/RUDE` | TI 手册有 run state，但 polite/rude 不作为 CPU run 状态差异描述 | RTL 二者都并入 `ET_W_CPU_Run` | 当前二者 run 现象基本一致 |
| `STEP_POLITE/RUDE` | TI 手册区分 RUN1/STEP1 的 interrupt 服务规则；polite/rude 属于 access 语义 | RTL 二者都并入 `ET_W_CPU_Step` | 当前二者 step 现象基本一致 |
| `FREE_RUN` | TI TRM 中 free-run 多用于外设 emulation suspend 时继续运行 | RTL `FreeRun` 仅并入 `ET_W_CPU_Run` | 当前 CPU 侧等价普通 run |
| CPU reset command | TI 手册描述 RS/reset 与 real-time debug 关系 | RTL 用 `SET_RESET + 85FF` 私有 command 触发 `ET_W_CPU_Reset` | 行为方向一致，opcode/协议私有 |
| `nb_step/clr_step` | TI 手册没有该命令名 | RTL 复用 `85FF`，无 set_reset 时 step，同时清 set_reset | RTL 私有 flow |
| ESTOP flush | TI 手册描述 ESTOP 与 pipeline/step 语义 | RTL 显式 `ET_W_Flush_Fetch_Pipeline` | 合理实现细节，手册不直接列该信号 |
| Watchpoint stop point | TI 手册说明 read/write watchpoint 停止点可能滞后数条指令 | RTL 有 `WP_Halt` 与 DBGSTAT[12] | 还需完整 seq 验证 |
| Data logging | TI 手册详细定义 DMA_CNTRL/EVT_CNTRL claim/enable/complete | RTL 有 DMA/INT/FIFO 相关寄存器 | 当前 UVM 未完整验证 |

### 18.4 Real-time + DBGM 一致性重点

TI C28x 手册描述：

- Real-time mode 用于 background code halt 时继续服务 time-critical interrupt。
- `DBGM=1` 会禁止或延迟 debug event/debug access。
- 在 real-time mode 下，如果单步的指令设置了 `DBGM`，CPU 可能继续执行直到 `DBGM` 清除。

当前 RTL 对应：

```verilog
if (ET_W_CPU_Halt) begin
    if (ST1_DBGM && ET_W_Real_Time_Mode)
        CPU_State_Next = CPU_RUN;
    else
        CPU_State_Next = CPU_DEBUG_HALT;
end
```

以及 step 完成时：

```verilog
if ((Inst_Count == 1) && D2_To_W_Is_Flushed) begin
    if (ST1_DBGM && ET_W_Real_Time_Mode)
        CPU_State_Next = CPU_RUN;
    else
        CPU_State_Next = CPU_DEBUG_HALT;
end
```

评估：

- 这是当前 RTL 与 TI 手册最关键、最一致的点。
- 验证普通 halt/step 前应先 `RT_DISABLE`。
- 专门验证 real-time mode 时，应构造 `ST1.DBGM=1` 场景，期望 halt/step 可能不保持 halt。

### 18.5 Polite / Rude 一致性评估

TI 手册中 polite/rude 的核心定义出现在 DT-DMA 机制：

| 类型 | `DBGM=0` | `DBGM=1` |
|---|---|---|
| polite access | 允许 | 不允许/等待 |
| rude access | 允许 | 忽略 DBGM，仍允许 |

当前 RTL 现状：

- `CD.v` 对 halt/run/step 分别译码 polite/rude opcode。
- `ET_W_CPU_Polite` 被生成，但对 `CPU_ET.v` 状态跳转没有实际影响。
- `AD.v` 中有 `reg_DMA_CNTRL[9]`、`reg_DMA_CNTRL[14]` 等 polite/priority 相关控制。

评估：

- 对 CPU 控制命令，polite/rude 目前是 opcode 覆盖点，不是行为差异点。
- 对 memory/data logging/DT-DMA 访问，后续应补 `DBGM=1` 的 polite/rude case 才能确认是否完全符合 TI 语义。

推荐验证：

```text
1. 让 CPU 设置 ST1.DBGM=1。
2. RT_ENABLE。
3. 做 polite memory/emureg read/write。
4. 做 rude memory/emureg read/write。
5. 比较 polite 是否等待/失败，rude 是否成功。
6. 清 DBGM 后确认 polite 恢复。
```

### 18.6 ESTOP 一致性评估

TI 手册：

- `ESTOP0` opcode 为 `0111_0110_0010_0101`，即 `16'h7625`。
- `ESTOP1` opcode 为 `0111_0110_0010_0100`，即 `16'h7624`。
- `ESTOP0` 不增加 PC。
- `ESTOP1` halt 前 PC 指向下一条。
- 若 emulator 未连接或 emulation disabled，ESTOP 可按 NOP 行为处理。

当前 RTL：

```verilog
I_ESTOP0 = D1_W_Active_Next &&
           (D1_B_Field_LSW_Next == 16'b0111_0110_0010_0101) &&
           ET_W_EMU_Active && !D2_W_Stall_D1;

ESTOP1_D1 = D1_W_Active_Next &&
            (D1_B_Field_LSW_Next == 16'b0111_0110_0010_0100) &&
            ET_W_EMU_Active && !D2_W_Stall_D1 && !D2_W_Flush_Fetch_Pipeline;
```

评估：

- opcode 完全一致。
- emulation active gating 与 TI “emulator connected/emulation enabled” 语义一致。
- DBGSTAT[10]/[11] 原因位符合软件断点原因记录需求。
- PC 是否严格满足 ESTOP0 不增加、ESTOP1 指向下一条，需要专门 C case 和 PC checker 验证。

### 18.7 Analysis breakpoint / watchpoint 一致性评估

TI 手册：

- Analysis breakpoint 是硬件断点，不修改程序代码。
- 通过 program address bus comparator 匹配断点地址和 mask。
- 指令进入 D2 前触发 halt。
- Watchpoint 可以按 address 或 address+data 触发，read/write 停止点可能不同。

当前 RTL：

- AU0/AU1 有 address mask、address、control register。
- AU0 exact PC breakpoint 已经通过 `0x828/0x82A/0x82E` flow 跑通。
- `DBGSTAT[14]` 记录 HWBP halt。
- `DBGSTAT[12]` 预留/实现 WP halt 记录。

评估：

- AU0 hardware breakpoint 与 TI analysis breakpoint 语义一致。
- Watchpoint 方向一致，但尚未通过 UVM seq 完整证明。
- 后续需补 read watchpoint、write watchpoint、address+data watchpoint。

### 18.8 Data logging 一致性评估

TI 手册：

- Data logging 通过 JTAG 将 memory buffer 传给 host。
- 软件需 claim resource，配置 start address/count/end address，再 enable。
- `DMA_CNTRL` 中包含 priority、polite/rude、ISR enable、end method、control/status。
- 完成后可触发 DLOGINT。

当前 RTL：

- 有 `reg_DMA_CNTRL`、`reg_DMA_ID`、`reg_INT`、FIFO count、DLOGINT 相关字段。
- reset 默认 `reg_DMA_CNTRL <= 16'h8000`。
- `0x83E` 可读 `{reg_DMA_ID, reg_DMA_CNTRL}`。
- `0x83C` 可读 `{..., ET_W_DLOGINT, ..., fifo_cnt}`。

评估：

- 寄存器结构与 TI data logging 方向一致。
- 当前尚未实现完整 UVM flow，因此不能确认 claim/enable/complete/DLOGINT 全部一致。
- data logging 应作为后续高级覆盖目标。

### 18.9 器件层 JTAG/CSM/ECSL 一致性

F28035 TRM 说明：

- JTAG pins 与 GPIO 复用。
- TRST/JTAGDEBUG 决定 JTAG enable/disable。
- CSM/ECSL 会限制 JTAG 对 secure memory 的访问。
- secure 场景下，JTAG 访问 protected memory 可能 trip ECSL，导致 emulation connection 断开。

当前 RTL/验证状态：

- TB 已处理 ET JTAG pad ownership，避免 boot subenv 与 ET JTAG 同时 drive。
- 当前 ET JTAG case 主要跑 unsecure SRAM `_a`，未覆盖 CSM/ECSL secure read。

评估：

- JTAG pad/boot 方向一致。
- CSM/ECSL 与 secure memory 的 JTAG 限制尚未通过 ET JTAG flow 验证。

### 18.10 一致性风险列表

| 风险 | 等级 | 说明 | 建议 |
|---|---|---|---|
| halt/run/step polite/rude 无行为差异 | 中 | 当前 RTL 对 CPU 控制命令基本等价 | 覆盖 opcode，但不要写差异 checker |
| FreeRun 等价 Run | 中 | 与外设 free-run 语义不同，不应过度解读 | checker 按 CPU run 处理 |
| TDO readback 未验证 | 中 | 当前 read 多数用 backdoor observe | 引入 SVT response compare |
| Watchpoint 未实测 | 中 | RTL 有 WP 路径，UVM 还未配置 AU watch | 补 read/write/data watchpoint seq |
| Data logging 未实测 | 中 | 寄存器存在，但完整 flow 未跑 | 补 claim/enable/complete/DLOGINT |
| CSM/ECSL 未实测 | 中 | secure JTAG 行为可能影响真实调试 | 补 secure memory JTAG read case |
| ESTOP PC 精确语义未实测 | 低/中 | opcode 已一致，但 PC 是否完全符合需看 case | 补 ESTOP0/1 C image |

### 18.11 一致性验证优先级

建议后续按以下顺序补齐：

1. `cmd_flow`: polite/rude/free-run/RT command decode 覆盖。
2. `reset_nbstep`: reset/nb_step/clr_step 覆盖。
3. `mem16_dbgstat`: 16-bit access 与 DBGSTAT 状态覆盖。
4. `estop_wait`: ESTOP0/ESTOP1 与 PC/DBGSTAT 覆盖。
5. `watchpoint`: read/write/address+data watchpoint 覆盖。
6. `polite_rude_dbmg`: `DBGM=1` 下 polite/rude memory access 区分。
7. `data_logging`: DMA_CNTRL/EVT_CNTRL/DLOGINT 覆盖。
8. `csm_ecsl_jtag`: secure memory JTAG access 限制覆盖。

### 18.12 最终评估

当前 ET JTAG RTL 可以认为已经覆盖并实现了 TI C28x emulation 的核心功能框架：

- CPU execution control: 一致。
- Real-time debug / DBGM: 一致且需要重点验证。
- ESTOP software breakpoint: opcode 完全一致。
- Analysis breakpoint: AU0 flow 与手册一致。
- Memory/emureg debug access: 架构一致。

当前不能直接宣称完全一致的部分：

- polite/rude DT-DMA 行为。
- watchpoint 停止点和原因位。
- data logging 完整协议。
- CSM/ECSL secure JTAG 限制。
- TDO 返回数据链路。

因此，验证结论建议写成：

```text
当前 RTL 与 TI C28x/F28035 emulation architecture 在 halt/run/step、
real-time mode、ESTOP、basic DT-DMA memory access、AU0 hardware breakpoint
方面一致；polite/rude access、watchpoint、data logging、CSM/ECSL 和 TDO
readback 仍需专项 case 完成一致性闭环。
```
