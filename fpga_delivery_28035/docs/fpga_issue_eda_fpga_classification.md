# FPGA 问题归因分析

> 更新时间：2026-09-03  
> 版本基线：本地 `fpga_delivery_28035` 当前保留的 8 条相关 case 已与远端 `/scratch/home/lcheng/work_0724/s03_sdk/example` 最新源码逐文件一致；`can_tx_std_ext_burst_basic` 已按结论从本地交付包及清单中删除。

## 使用说明

- 本文对 `spi_fifo_level_boundary_basic`、`can_global_mask_opcode_shadow_basic` 和 `sci_fifo_rx_basic` 的失败分析，针对的是修复前版本。当前交付源码已经更新，旧失败不能继续作为最新版 case 的测试结论。
- 上述 3 条修复版需重新完成 F28035、EDA 和 FPGA 对照；复测前状态统一记为“已修复，待复测”，不能提前判定通过。
- `gpio_output_basic` 的 EDA 功能链路已有完整波形闭环，现有 FPGA 归因仍然有效。
- `can_tx_std_ext_burst_basic` 不属于当前交付范围，只有在 case 补齐 ACK/RX 条件并通过 F28035 基准验证后，才考虑重新加入。

## 结论概览

本文根据 F28035 对照结果、EDA 波形、DSS runtime 状态、fail code 和源码断言，对 9 条 case 进行归因。`connect/load/run/halt/diagnostics PASS` 只能排除构建和 DSS 控制问题，不能证明外设功能正确。

| Case | 主要归因 | 置信度 | 当前状态 |
|---|---|---:|---|
| `spi_fifo_level_boundary_basic` | Case/EDA 检查问题，不是 FPGA 缺陷 | 高 | 本地与远端已同步修复，需复测 |
| `can_global_mask_opcode_shadow_basic` | Case 前置条件缺失，不是 FPGA 缺陷 | 高 | 本地与远端已同步修复，需复测 |
| `gpio_output_readback_basic` | 倾向 FPGA 顶层回采或 pin mapping | 中 | F28035 通过，待补同层级 EDA 动态波形 |
| `gpio_output_basic` | FPGA 顶层、综合实现或 pin mapping | 高 | F28035 和 EDA RTL 均通过，FPGA 失败 |
| `gpio_direction_switch_basic` | 倾向 FPGA GPIO34 DIR/回采链路 | 中 | F28035 通过，但原 OR 判据尚未拆分 |
| `can_selftest_mode_toggle_basic` | 倾向 FPGA eCAN 配置模式握手；case 另有无限等待问题 | 中 | 停在 `CCR -> CCE`，尚未进入收发 |
| `can_extid_filter_basic` | 证据不足，暂不能归因 | 低 | 缺少原始 fail code 和 eCAN 寄存器快照 |
| `can_tx_std_ext_burst_basic` | Case/测试条件问题，不是 FPGA 缺陷 | 高 | F28035 原生失败，已从本地交付删除 |
| `sci_fifo_rx_basic` | Case 初始化/诊断问题，不是 FPGA 缺陷 | 高 | 本地和远端已修，等待 F28035 复测 |

## 当前交付状态

| Case | 本地与远端源码 | 交付状态 | 下一步 |
|---|---|---|---|
| `spi_fifo_level_boundary_basic` | 一致 | 保留，已修复 | 复测 FIFO `0 -> 4 -> 0` 边界行为 |
| `can_global_mask_opcode_shadow_basic` | 一致 | 保留，已修复 | 复测 RX MBOX1、自测 ACK、mask/opcode 和数据回读 |
| `gpio_output_readback_basic` | 一致 | 保留 | 补 FPGA GPIO34 输出回采链路观测 |
| `gpio_output_basic` | 一致 | 保留 | 检查 FPGA pad wrapper、综合连接和 pin mapping |
| `gpio_direction_switch_basic` | 一致 | 保留 | 拆分 GPBDIR 与 GPBDAT 失败条件后复测 |
| `can_selftest_mode_toggle_basic` | 一致 | 保留 | 定位 FPGA `CCR -> CCE` 握手，并处理无限等待风险 |
| `can_extid_filter_basic` | 一致 | 保留 | 获取 fail code 与 mailbox/eCAN 寄存器快照 |
| `sci_fifo_rx_basic` | 一致 | 保留，已修复 | 使用分阶段失败码和寄存器快照重新对照 |
| `can_tx_std_ext_burst_basic` | 不适用 | 已删除 | 修复测试前置条件并通过 F28035 后再评估恢复 |

## 逐项分析

### 1. spi_fifo_level_boundary_basic

- 问题版本只向 `SPITXBUF` 写入一个 word，随后立即要求 `TXFFST != 0`。
- 单 word 可能已被 shift path 消费，`TXFFST=0` 是允许出现的瞬时状态，原判据不成立。
- EDA 调试还暴露过 FIFO 深度按 16 检查、scoreboard 硬编码期望 1 的问题；RTL 实际 FIFO 深度为 4。
- 远端已改为保持移位器 reset、按 4-word 深度检查 `0 -> 4 -> 0`，scoreboard 改为累计写入计数。

结论：原失败属于 **case 与 EDA checker 建模问题**，不能归因 FPGA SPI RTL。本地交付现已与远端修复版同步，取得稳定复测结果后再用于 FPGA。

### 2. can_global_mask_opcode_shadow_basic

- 原版本只配置 TX MBOX0，没有配置匹配的 RX MBOX1，却等待 TX ACK。
- self-test 场景缺少接收 mailbox/ACK 前置条件，可能导致等待不结束。
- 远端当前版本已增加 RX MBOX1，并保留 `CANGAM`、`CANOPC` shadow readback 与数据检查。

结论：原失败属于 **case 配置缺失**，不是 FPGA eCAN RTL 证据。本地交付现已与远端修复版同步，仍需完成复测。

### 3. gpio_output_readback_basic

- FPGA 在 GPIO34 输出高电平读回阶段失败。
- F28035 对照通过，构建和 DSS 流程正常。
- `GPBDAT.GPIO34` 返回 pad 输入回采值，而不是单纯的输出 latch，因此 FPGA 顶层未做输出到输入回采、pad wrapper 行为不同或 pin mapping 错误都可能导致失败。

结论：**倾向 FPGA 顶层回采或引脚映射问题**。建议补采 `gpbdat_latch[2]`、`gpio34_pad_out_mux`、`gpio34_pad_out_en_mux`、`gpio34_pad_in`、`gpioin[34]` 和 GPBDAT read data 后再升级为确认结论。

### 4. gpio_output_basic

- F28035 对照通过，FPGA 在 `GPBSET.GPIO34=1` 后读取 `GPBDAT.GPIO34` 失败。
- EDA 波形已确认 `gpbdir[2]`、`gpbset_pulse[2]`、`gpbdat_latch[2]`、GPIO34 mux/OE、`gpio34_pad_in`、`gpio34_dat` 和 `gpioin[34]` 全部正确。
- EDA 读事务为 `PF1_B_Raddr=22'h006FC8`、`gpbdat_rd_hit=2'b01`，`GPIO_B_PF1_Rdata=32'h00001FFF`，其中 bit2 为 1。

结论：case、GPIO 源 RTL 和 EDA read mux 已闭环通过。该问题应归为 **FPGA 综合后实现、顶层 pad wrapper、输出回采连接或 GPIO34 pin mapping**。

### 5. gpio_direction_switch_basic

- F28035 对照通过，FPGA 在输出高阶段失败。
- `src/main.c` 使用 `(GPBDIR.GPIO34 != 1) || (GPBDAT.GPIO34 != 1)`，同一个 fail code 无法区分 DIR readback 与 pad readback。
- 后续 input 和 output-low 阶段没有执行，因此目前只知道第一次输出高检查失败。

结论：**倾向 FPGA GPIO34 方向控制或输出回采链路**，但证据尚未精确到子条件。需要分别读取 `GPBDIR[2]` 和 `GPBDAT[2]`，或拆分失败码。

### 6. can_selftest_mode_toggle_basic

- FPGA 写 `CANMC.CCR=1` 后，`CANES.CCE` 未置位，程序停在进入配置模式的等待循环，尚未执行 CAN 收发。
- RTL 中 CCE 置位依赖 `ccr && (bus_idle || brp_zero || bus_tec)`。
- 应检查 `ECANA_CLK`、`wel_canmc`、`eallow`、`sleepn`、`ccr`、`bus_idle`、`brp_zero`、`bus_tec`、`cce` 和 CANRX 电平。
- 公共 helper 对 CCE 使用无限轮询，因此功能异常会表现为外部 timeout，这是 case 健壮性问题，但不是 CCE 不置位的根因。

结论：当前 **倾向 FPGA eCAN 时钟、CANRX/bus-idle 环境或 CCR-to-CCE 状态路径**。若 F28035 同版本能通过，该结论可提升为 FPGA 问题；同时建议单独修复无限等待。

### 7. can_extid_filter_basic

- 当前只确认 DSS connect/load/run/halt/diagnostics 完成。
- case 包含不匹配 ID 拒收、匹配 ID 接收、TX ACK、RX pending 和 64-bit 数据检查多个断言。
- 缺少原始 fail code、`CANTA`、`CANRMP`、`CANES`、MBOX1 `MSGID/MDL/MDH` 快照，无法确定失败阶段。

结论：**暂不能判断是 EDA/case 还是 FPGA RTL**。需要先根据 `0x5401` 至 `0x5406` 的 fail code 确定具体分叉点。

### 8. can_tx_std_ext_burst_basic

- F28035 原生在第一帧标准 ID `0x055` 等待 `CANTA.bit0` 超时。
- 失败位置为 `src/main.c:61`，`fail_code=0x63A1`。
- 原 case 只配置 TX MBOX0，默认 self-test 会自行完成 ACK，但没有匹配 RX mailbox 或外部 ACK 节点。

结论：属于 **case/测试条件问题**，不能作为 FPGA RTL 缺陷证据。该 case 已从本地 FPGA 交付包删除。

### 9. sci_fifo_rx_basic

- F28035 原生在 RX FIFO level 检查失败，`PC=0x000089C3`，旧版 `fail_code=0xB0C5`。
- 旧版将 tag、基础错误码和完整 `SCIFFRX` 相加后再由 16-bit runtime 上报，无法唯一还原失败向量和寄存器状态。
- 当前本地与远端已增加显式 TX/RX FIFO reset 边沿、初始化读回、四阶段独立失败码以及 `SCIFFRX/SCIFFTX` 快照；原 4/3/2/2 字节激励保持不变。

结论：原失败属于 **case 初始化和诊断不足**，不能归因 FPGA SCI RTL。修复版必须先在 F28035 稳定通过，再恢复 FPGA 对照资格。

## 建议处理顺序

1. 优先检查 `gpio_output_basic` 的 FPGA 顶层 GPIO34 回采和 pin mapping，这是当前证据最完整的 FPGA 问题。
2. 对 `gpio_output_readback_basic`、`gpio_direction_switch_basic` 复用同一组 GPIO34 ILA 信号，确认是否为同一个根因。
3. 对 `can_selftest_mode_toggle_basic` 抓取 CCR/CCE、eCAN clock、CANRX 和 bus_idle，定位配置模式握手。
4. 为 `can_extid_filter_basic` 补齐原始 fail code 和 mailbox 快照后再归因。
5. `spi_fifo_level_boundary_basic`、`can_global_mask_opcode_shadow_basic`、`sci_fifo_rx_basic` 使用修复版先完成 F28035 和 EDA 回归。
6. `can_tx_std_ext_burst_basic` 保持从 FPGA 交付中移除，修复并在 F28035 通过后再评估是否恢复。
