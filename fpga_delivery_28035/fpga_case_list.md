# 28035 FPGA 对比验证候选 case 清单

> 来源：`/scratch/home/lcheng/work_0724/s03_sdk/example`，JTAG 条目提取自两个仓库的 `origin/et_jtag`。清单优先选择 FPGA/真实芯片上较容易复现的内部 loopback、寄存器自检、中断/复位/引脚可观测 case。

- 更新时间：2026-09-03
- 总数：149 条，15 个模块
- 本次新增模块：`JTAG`

| No | Module | Case | 功能点 | FPGA 需求 | 预期结果 | 风险 |
|---:|---|---|---|---|---|---|
| 1 | LIN | `lin_reg_if_rw_basic` | 寄存器读写 smoke | 纯 C 自检 | PASS trap；关键 LIN 寄存器 readback 一致 | 低 |
| 2 | LIN | `lin_baud_program_basic` | LIN/SCI baud prescaler 配置 | 纯 C 自检 | BRSR/baud 相关寄存器 readback 一致 | 低 |
| 3 | LIN | `lin_iodft_loopback_basic` | LIN IODFT/loopback 路径 | 内部 loopback | TX/RX loopback 数据或状态符合预期 | 中 |
| 4 | LIN | `lin_top_mode_loopback_power_cross_basic` | LIN/SCI mode 与 power loopback 交叉 | 内部 loopback | 模式切换后寄存器/flag 正确，PASS | 中 |
| 5 | LIN | `lin_rx_checksum_length_real_basic` | RX checksum/length 边界 | 需 LIN RX 激励或板级 loopback | RX 数据长度/checksum flag 符合预期 | 中 |
| 6 | LIN | `lin_tx_checksum_ext_real_basic` | TX enhanced checksum 路径 | 可用 LIN pin/loopback 观察 | TX checksum/数据发送完成，PASS | 中 |
| 7 | LIN | `lin_sci_multibuf_rdslot_sweep_basic` | SCI multi-buffer read slot sweep | 纯 C/内部路径 | 多 buffer slot readback/flag 清除正确 | 中 |
| 8 | LIN | `lin_rx_rxcnt_num_boundary_real_basic` | RX counter/buffer 边界 | 需 RX 激励或 loopback | RXCNT/NUM 边界状态正确 | 中 |
| 9 | LIN | `lin_header_break_sync_master_basic` | LIN master header break/sync | LIN TX pin/ILA 观察 | LINTX 出现 break/sync/header 序列，PASS | 中 |
| 10 | LIN | `lin_wakeup_break_flag_route_basic` | wakeup/break flag route | LIN pin/状态观察 | wakeup/break flag set/clear 路径正确 | 中 |
| 11 | SPI | `spi_internal_loopback_basic` | SPI 内部 loopback smoke | 内部 loopback | RX pattern 等于 TX pattern，PASS | 低 |
| 12 | SPI | `spi_loopback_mode_matrix_basic` | SPI loopback mode matrix | 内部 loopback | 不同模式 loopback 数据一致 | 低 |
| 13 | SPI | `spi_multiple_frame_loopback_basic` | 多帧 loopback | 内部 loopback | 多帧 TX/RX 顺序和数据一致 | 低 |
| 14 | SPI | `spi_triwire_loopback_basic` | 3-wire loopback | 内部/板级 loopback | SIMO/SOMI 单线方向切换和数据一致 | 中 |
| 15 | SPI | `spi_charlen_sweep_basic` | 字符长度 sweep | 内部 loopback | 不同 charlen 下 RX/TX 数据 mask 正确 | 低 |
| 16 | SPI | `spi_fifo_level_boundary_basic` | FIFO level 边界 | 纯 C 自检 | TX/RX FIFO level/flag 边界正确 | 低 |
| 17 | SPI | `spi_fifo_tx_boundary_basic` | TX FIFO 边界 | 纯 C/loopback | TX FIFO flag 和发送完成正确 | 低 |
| 18 | SPI | `spi_fifo_rx_boundary_basic` | RX FIFO 边界 | 内部 loopback | RX FIFO flag/level 正确 | 低 |
| 19 | SPI | `spi_nonfifo_intflag_irq_basic` | 非 FIFO interrupt flag | 纯 C 自检 | INT flag set/clear 正确 | 低 |
| 20 | SPI | `spi_reg_if_rw_basic` | SPI register read/write | 纯 C 自检 | 寄存器 readback 正确 | 低 |
| 21 | CAN | `can_reset_default_state_basic` | eCAN reset default | 纯 C 自检 | 复位默认寄存器状态正确 | 低 |
| 22 | CAN | `can_pin_mux_basic` | eCAN pin mux | 寄存器/引脚 mux | CANTX/CANRX mux 配置 readback 正确 | 低 |
| 23 | CAN | `can_selftest_mode_toggle_basic` | eCAN self-test mode | 内部 self-test | self-test 模式切换和状态正确 | 中 |
| 24 | CAN | `can_extid_filter_basic` | extended ID filter | 内部 mailbox/filter | extended ID mask/filter 命中/未命中符合预期 | 中 |
| 25 | CAN | `can_rx_extid_dlc_sweep_basic` | RX ext-id DLC sweep | 需 CAN 激励或 self-test | RX mailbox data/DLC/RMP 正确 | 中 |
| 26 | CAN | `can_mailbox32_shadow_sweep_basic` | 32 mailbox shadow sweep | 纯 C 自检 | mailbox control/data shadow readback 正确 | 低 |
| 27 | CAN | `can_status_flag_clear_basic` | status flag clear | 纯 C 自检 | CANES/GIF 等 W1C/clear 行为正确 | 低 |
| 28 | CAN | `can_interrupt_dual_line_basic` | interrupt dual line | 中断/PIE 观察 | INT0/INT1 route 和 flag/vector 正确 | 中 |
| 29 | CAN | `can_global_mask_opcode_shadow_basic` | global mask/shadow | 纯 C 自检 | CANGAM/LAM/shadow readback 正确 | 低 |
| 30 | PIE | `pie_irq_single_source` | PIE single interrupt source | 纯 C/中断自检 | 单源 IFR/IER/ACK/vector 路径正确 | 低 |
| 31 | PIE | `pie_mask_ack_basic` | PIE mask/ack | 纯 C 自检 | IER mask 与 PIEACK 清除正确 | 低 |
| 32 | PIE | `pie_irq_ack_holdoff_release_basic` | ACK holdoff/release | 纯 C/中断自检 | ACK holdoff 后释放能重新响应 | 中 |
| 33 | PIE | `pie_vector_table_fill_u16_basic` | vector table u16 fill | 纯 C 自检 | vector table halfword 写读一致 | 低 |
| 34 | PIE | `pie_vector_table_fill_u32_basic` | vector table u32 fill | 纯 C 自检 | vector table word 写读一致 | 低 |
| 35 | PIE | `pie_vector_table_rw_inline_u16_basic` | vector inline u16 RW | 纯 C 自检 | inline vector halfword RW 正确 | 低 |
| 36 | PIE | `pie_regs_xint_readhit_mode_counter_basic` | XINT readhit/mode/counter | GPIO/XINT 或寄存器自检 | XINTCR/XINTCTR readback/counter 正确 | 中 |
| 37 | PIE | `pie_xint_counter_readmux_basic` | XINT counter readmux | GPIO/XINT 或寄存器自检 | XINT counter mux 读值正确 | 中 |
| 38 | PIE | `pie_soc_gpio_xint123_basic` | GPIO XINT1/2/3 SoC path | 需要 GPIO 输入/ILA | GPIO pulse 进入 XINT/PIE，CPU 中断可观测 | 中 |
| 39 | PIE | `pie_soc_direct_cpu_irq_nmi_timer_basic` | NMI/TIMER direct CPU irq | SoC 集成观察 | NMI/TINT1/TINT2 直连 CPU 中断路径可观测 | 中 |
| 40 | WDG_SYS | `watchdog_disable_test` | watchdog disable | 纯 C 自检 | WD disable 后不复位，PASS | 低 |
| 41 | WDG_SYS | `watchdog_key_sequence_test` | WDKEY 正确序列 | 纯 C 自检 | 正确喂狗序列不触发 reset | 低 |
| 42 | WDG_SYS | `watchdog_prescaler_test` | watchdog prescaler | 纯 C/计时观察 | prescaler 配置 readback/timeout 行为正确 | 中 |
| 43 | WDG_SYS | `watchdog_wdflag_test` | WDFLAG 行为 | 纯 C 自检 | WDFLAG set/clear 路径正确 | 中 |
| 44 | WDG_SYS | `watchdog_intr_mode_test` | watchdog interrupt mode | 中断观察 | WDINT 产生且可清除 | 中 |
| 45 | WDG_SYS | `watchdog_reset_mode_test` | watchdog reset mode | 复位观察 | WD reset 发生并重新启动应用 | 中 |
| 46 | WDG_SYS | `sys_watchdog_timeout_basic` | SYS watchdog timeout | 复位/flag 观察 | timeout 后 flag/状态符合预期 | 中 |
| 47 | WDG_SYS | `sys_watchdog_timeout_reset` | watchdog timeout reset | 复位重启观察 | reset 后 WDFLAG set，应用 pass | 中 |
| 48 | WDG_SYS | `sys_wdg_wdchk_wrong_key` | WDCHK wrong key reset | 复位重启观察 | wrong key 触发 reset，重启后 pass | 中 |
| 49 | WDG_SYS | `sys_lpm_idle_watchdog_basic` | LPM idle watchdog | 低功耗+WDG | IDLE 下 watchdog wake/reset 路径正确 | 中 |
| 50 | SCI | `sci_internal_loopback_basic` | SCI internal loopback | 内部 loopback | RX data 等于 TX pattern，PASS | 低 |
| 51 | SCI | `sci_loopback_data_pattern_basic` | SCI loopback pattern | 内部 loopback | 多 pattern loopback 正确 | 低 |
| 52 | SCI | `sci_fifo_rx_basic` | SCI RX FIFO basic | 内部/外部 RX | RX FIFO level/data 正确 | 中 |
| 53 | SCI | `sci_fifo_reset_then_loopback_basic` | FIFO reset 后 loopback | 内部 loopback | FIFO reset 后可正常 TX/RX | 低 |
| 54 | SCI | `sci_txrdy_int_nonfifo_basic` | TXRDY nonfifo irq | 中断观察 | TXRDY/INT flag 行为正确 | 低 |
| 55 | SCI | `sci_rxrdy_clear_on_read_basic` | RXRDY read clear | 内部/外部 RX | 读 RXBUF 后 RXRDY 清除 | 中 |
| 56 | SCI | `sci_sciccr_charlen_sweep_basic` | SCI charlen sweep | 内部 loopback | 不同 charlen 数据 mask 正确 | 低 |
| 57 | SCI | `sci_stop2_parity_charlen_sweep_basic` | stop/parity/charlen | 内部 loopback | stop/parity/charlen 组合自检通过 | 中 |
| 58 | SCI | `sci_baud_program_basic` | SCI baud program | 纯 C 自检 | baud 寄存器 readback 正确 | 低 |
| 59 | SCI | `sci_reg_if_rw_basic` | SCI register RW | 纯 C 自检 | 寄存器 readback 正确 | 低 |
| 60 | GPIO | `gpio_output_basic` | GPIO output | 引脚/寄存器观察 | GPIO 输出置位/清零正确 | 低 |
| 61 | GPIO | `gpio_input_basic` | GPIO input | 外部输入或 loopback | GPIO input data 采样正确 | 中 |
| 62 | GPIO | `gpio_toggle_basic` | GPIO toggle | 引脚观察 | GPIO pin toggle 可见 | 低 |
| 63 | GPIO | `gpio_output_readback_basic` | GPIO output readback | 纯 C/引脚观察 | 输出锁存 readback 正确 | 低 |
| 64 | GPIO | `gpio_direction_switch_basic` | GPIO direction switch | 引脚/寄存器观察 | DIR 切换后输入输出行为正确 | 低 |
| 65 | GPIO | `gpio_mux_basic` | GPIO mux basic | 寄存器/引脚 mux | mux 配置 readback 正确 | 低 |
| 66 | GPIO | `gpio_mux_dynamic_switch_basic` | GPIO dynamic mux switch | 寄存器/引脚 mux | 动态 mux 切换后路径正确 | 中 |
| 67 | GPIO | `gpio_xint_rising_basic` | XINT rising | 外部 GPIO pulse | 上升沿触发 XINT/PIE | 中 |
| 68 | GPIO | `gpio_xint_falling_basic` | XINT falling | 外部 GPIO pulse | 下降沿触发 XINT/PIE | 中 |
| 69 | GPIO | `gpio_pin_walk_basic` | GPIO pin walk | 引脚/ILA 观察 | pin walk pattern 可观测 | 低 |
| 70 | EPWM | `epwm_up_aq_smoke` | up-count AQ smoke | PWM 输出观察 | EPWMxA/B 波形 duty/period 符合配置 | 低 |
| 71 | EPWM | `epwm_updown_aq_smoke` | up-down AQ smoke | PWM 输出观察 | 对称 PWM 波形符合配置 | 低 |
| 72 | EPWM | `epwm_deadband_smoke` | dead-band smoke | PWM 输出观察 | A/B dead-band 延迟可见 | 低 |
| 73 | EPWM | `epwm_event_int_soca_smoke` | event interrupt/SOCA | 中断/ADC SOC 观察 | ET flag/SOCA/INT 行为正确 | 中 |
| 74 | EPWM | `epwm_event_socb_smoke` | SOCB event | ADC SOC/flag 观察 | SOCB event flag 正确 | 中 |
| 75 | EPWM | `epwm_tripzone_swforce_ost_smoke` | TZ software OST | PWM 输出/flag 观察 | TZ force 后输出进入安全态 | 中 |
| 76 | EPWM | `epwm_reg_rw_smoke` | EPWM register RW | 纯 C 自检 | 寄存器 readback 正确 | 低 |
| 77 | EPWM | `epwm_clkdiv_hspclkdiv_matrix` | clock divider matrix | PWM 周期观察 | 不同 divider 下周期变化正确 | 中 |
| 78 | EPWM | `epwm_cmp_boundary_matrix` | compare boundary | PWM 输出观察 | CMP=0/PRD/boundary 行为正确 | 中 |
| 79 | EPWM | `epwm_tz_external_tz1_ost` | external TZ1 OST | 需外部 TZ1 输入 | 外部 TZ1 触发 trip，输出安全态 | 高 |
| 80 | EQEP | `eqep_count_basic` | QEP count basic | QEP 输入或 loopback | position counter 计数方向/数值正确 | 中 |
| 81 | EQEP | `eqep_unit_timer` | unit timer | 纯 C/中断观察 | unit timer flag/interrupt 正确 | 低 |
| 82 | EQEP | `eqep_unit_timeout_test` | unit timeout | 纯 C/中断观察 | UTO flag 行为正确 | 低 |
| 83 | EQEP | `eqep_watchdog_timeout_test` | QEP watchdog timeout | 纯 C/中断观察 | QEP watchdog flag/interrupt 正确 | 中 |
| 84 | EQEP | `eqep_compare_output_pulse` | position compare output | 输出/ILA 观察 | compare match pulse 可见 | 中 |
| 85 | EQEP | `eqep_register_wr` | register write/read | 纯 C 自检 | 寄存器 readback 正确 | 低 |
| 86 | EQEP | `eqep_mode_test` | mode test | QEP 输入或寄存器自检 | 不同 QEP mode 状态正确 | 中 |
| 87 | EQEP | `eqep_polarity_test` | polarity test | QEP 输入 | 输入极性翻转后计数方向符合预期 | 中 |
| 88 | EQEP | `eqep_interrupt_gate` | interrupt gate | 中断观察 | interrupt enable/mask/flag 正确 | 低 |
| 89 | EQEP | `eqep_reset_fsm_matrix` | reset FSM matrix | 复位/状态观察 | reset 后 FSM/state 恢复正确 | 中 |
| 90 | ADC | `adc_reg_rw_smoke` | ADC register RW | 纯 C 自检 | ADC 寄存器 readback 正确 | 低 |
| 91 | ADC | `adc_single_soc_basic` | single SOC | ADC 输入/模型 | 单 SOC 转换完成，RESULT 正确或稳定 | 中 |
| 92 | ADC | `adc_multi_soc_sw_trigger` | multi SOC SW trigger | ADC 输入/模型 | 多 SOC 顺序和 EOC 正确 | 中 |
| 93 | ADC | `adc_eoc_irq_basic` | EOC interrupt | 中断观察 | EOC/ADCINT 产生并清除 | 中 |
| 94 | ADC | `adc_int_continuous_mode` | continuous interrupt | 中断观察 | continuous mode 下 interrupt re-arm 正确 | 中 |
| 95 | ADC | `adc_int_noncont_overflow` | non-cont overflow | 中断/flag 观察 | overflow flag set/clear 正确 | 中 |
| 96 | ADC | `adc_clkdiv2en_basic` | ADC clock divider | 纯 C/时钟观察 | CLKDIV2EN readback/时序正确 | 低 |
| 97 | ADC | `adc_socctl_config_sweep` | SOCCTL config sweep | 纯 C 自检 | SOCCTL channel/trigger/acqps readback 正确 | 低 |
| 98 | ADC | `adc_trig_timer0_basic` | timer0 trigger | Timer+ADC 集成 | Timer0 触发 ADC EOC | 中 |
| 99 | ADC | `adc_reset_semantics` | ADC reset semantics | 纯 C 自检 | reset 后寄存器/状态恢复默认 | 低 |
| 100 | I2C | `i2c_master_write_1byte_basic` | I2C master write 1 byte | 需 I2C slave/loopback 模型 | 写 1 byte 完成，无 NACK | 中 |
| 101 | I2C | `i2c_master_read_1byte_basic` | I2C master read 1 byte | 需 I2C slave | 读 1 byte 数据符合预期 | 中 |
| 102 | I2C | `i2c_master_write_then_read_4byte_basic` | write then read 4 byte | 需 I2C slave | 写后读数据一致 | 中 |
| 103 | I2C | `i2c_master_write_8byte_pattern` | write 8 byte pattern | 需 I2C slave | 8 byte pattern 被 slave 接收 | 中 |
| 104 | I2C | `i2c_master_read_8byte_basic` | read 8 byte | 需 I2C slave | 8 byte readback 正确 | 中 |
| 105 | I2C | `i2c_master_write_back_to_back` | back-to-back write | 需 I2C slave | 连续写状态/flag 正确 | 中 |
| 106 | I2C | `i2c_master_read_back_to_back_basic` | back-to-back read | 需 I2C slave | 连续读状态/flag 正确 | 中 |
| 107 | I2C | `i2c_master_reg_readback_sweep` | I2C reg readback | 纯 C 自检 | I2C 寄存器 readback 正确 | 低 |
| 108 | I2C | `i2c_master_addr_nack_stop_basic` | address NACK stop | 需可控 slave/NACK | NACK 后 STOP/flag 正确 | 高 |
| 109 | I2C | `i2c_master_repeated_start_write_then_read_4byte_basic` | repeated-start WR/RD | 需 I2C slave | repeated start 时序和数据正确 | 中 |
| 110 | SYS_CLK | `sys_reset_release_basic` | reset release basic | 复位观察 | XRS release 后 CPU 正常启动 | 低 |
| 111 | SYS_CLK | `sys_pll_lock_basic` | PLL lock | 时钟/寄存器观察 | PLL lock/status 正确 | 中 |
| 112 | SYS_CLK | `sys_pll_bypass_basic` | PLL bypass | 时钟观察 | bypass 下 SYSCLK 切换正确 | 中 |
| 113 | SYS_CLK | `sys_divsel_roundtrip_basic` | DIVSEL roundtrip | 时钟/寄存器观察 | DIVSEL 切换和 readback 正确 | 中 |
| 114 | SYS_CLK | `sys_xclkout_div_basic` | XCLKOUT divider | XCLKOUT pin/ILA | XCLKOUT 分频正确 | 中 |
| 115 | SYS_CLK | `sys_intosc2_pll_basic` | INTOSC2 PLL | 时钟观察 | INTOSC2 到 PLL 路径正常 | 中 |
| 116 | SYS_CLK | `sys_osc1_osc2_roundtrip_basic` | OSC1/OSC2 roundtrip | 时钟源观察 | OSC1/OSC2 切换恢复正确 | 高 |
| 117 | SYS_CLK | `sys_lpm_idle_interrupt_basic` | LPM idle interrupt | 中断唤醒观察 | IDLE 后 interrupt wake 正确 | 中 |
| 118 | SYS_CLK | `sys_lpm_reg_access_basic` | LPM register access | 纯 C 自检 | LPMCR 等寄存器 readback 正确 | 低 |
| 119 | SYS_CLK | `sys_xrs_runtime_window_basic` | XRS runtime window | 复位观察 | runtime XRS window/reset 行为正确 | 中 |
| 120 | ECAP | `ecap_reg_rw_smoke` | eCAP register RW | 纯 C 自检 | ECAP 配置/状态寄存器 readback 正确 | 低 |
| 121 | ECAP | `ecap_capture_single_edge` | single-edge capture | 输入脉冲/FPGA harness | 单沿 capture timestamp/flag 正确 | 中 |
| 122 | ECAP | `ecap_capture_dual_edge` | dual-edge capture | 输入脉冲/FPGA harness | 双沿 capture 顺序和差值正确 | 中 |
| 123 | ECAP | `ecap_capture_quad_edge` | quad-edge capture | 输入脉冲/FPGA harness | 四级 capture FIFO/flag 正确 | 中 |
| 124 | ECAP | `ecap_capture_continuous_wrap` | continuous wrap capture | 输入脉冲/ILA | 连续 capture wrap 后状态正确 | 中 |
| 125 | ECAP | `ecap_capture_counter_reset` | capture counter reset | 输入脉冲/寄存器观察 | capture event 后 counter reset 行为正确 | 中 |
| 126 | ECAP | `ecap_capture_prescale_div2` | capture prescale div2 | 输入脉冲/ILA | prescale 后 capture event 间隔符合预期 | 中 |
| 127 | ECAP | `ecap_capture_wrap_matrix` | capture wrap matrix | 输入脉冲/ILA | 不同 stop/wrap 配置下 flag 顺序正确 | 中 |
| 128 | ECAP | `ecap_apwm_matrix` | APWM mode matrix | APWM 输出观察 | APWM period/duty 输出符合配置 | 中 |
| 129 | ECAP | `ecap_interrupt_integration` | eCAP interrupt integration | 中断/PIE 观察 | ECFLG/ECEINT/PIE 中断路径正确 | 中 |
| 130 | HRCAP | `hrcap_reg_rw_smoke` | HRCAP register RW | 纯 C 自检 | HRCAP 配置/状态寄存器 readback 正确 | 低 |
| 131 | HRCAP | `hrcap_normal_capture_rise` | normal rise capture | GPIO/输入脉冲 | 上升沿普通 capture 完成且结果有效 | 中 |
| 132 | HRCAP | `hrcap_normal_capture_fall` | normal fall capture | GPIO/输入脉冲 | 下降沿普通 capture 完成且结果有效 | 中 |
| 133 | HRCAP | `hrcap_hr_capture_rise` | high-resolution rise capture | GPIO/输入脉冲/ILA | 上升沿 HR capture result/flag 正确 | 中 |
| 134 | HRCAP | `hrcap_hr_capture_fall` | high-resolution fall capture | GPIO/输入脉冲/ILA | 下降沿 HR capture result/flag 正确 | 中 |
| 135 | HRCAP | `hrcap_capture_fifo_matrix` | capture FIFO matrix | 输入脉冲/状态观察 | FIFO level/overflow/读清路径正确 | 中 |
| 136 | HRCAP | `hrcap_counter_overflow_matrix` | counter overflow matrix | 状态/中断观察 | counter overflow flag/clear 行为正确 | 中 |
| 137 | HRCAP | `hrcap_interrupt_enable_clear_matrix` | interrupt enable/clear matrix | 中断/PIE 观察 | HRCAP interrupt enable/flag clear 路径正确 | 中 |
| 138 | HRCAP | `hrcap_clock_softreset_matrix` | clock/softreset matrix | 寄存器/状态观察 | clock gate/softreset 后寄存器和状态恢复正确 | 中 |
| 139 | HRCAP | `hrcap_dual_instance_gpio_matrix` | dual-instance GPIO matrix | GPIO/输入脉冲 | HRCAP 多实例输入选择和 capture 路径正确 | 中 |
| 140 | JTAG | `et_jtag_example` | 基础 halt/run/step/memory/AU0 流程 | 外部 JTAG 控制器，38-bit IR | CPU 状态切换、内存读写及 AU0 breakpoint 符合预期 | 中 |
| 141 | JTAG | `et_jtag_cmd_flow` | rude/polite halt/run/step、FreeRun、RT | 外部 JTAG 控制器，状态读取 | 各命令后 CPU/DBGSTAT 状态正确 | 中 |
| 142 | JTAG | `et_jtag_reset_nbstep` | set_reset、CPU reset、non-breakable step | JTAG reset/状态观察 | reset、nb_step 与 clr_step 路径正确 | 高 |
| 143 | JTAG | `et_jtag_mem16_dbgstat` | 16-bit memory 读写与 DBGSTAT | JTAG READA16/WRITEA16 | 低半字更新、读回及 DBGSTAT 正确 | 中 |
| 144 | JTAG | `et_jtag_tap_dr_sweep` | BYPASS/IDCODE/TESTMODE/DC_STRBS/DIR DR | 完整 TMS/TCK/TDI/TDO 接口 | DR 长度、选择及 TDO 数据符合协议 | 中 |
| 145 | JTAG | `et_jtag_tap_highz_bscan` | EXTEST/PRELOAD/HIGHZ boundary scan | 板级 BSR/pad 观察 | 指令选择、边界扫描移位和 HIGHZ 行为正确 | 高 |
| 146 | JTAG | `et_jtag_tap_pause` | Pause-DR/IR 与 Exit2 状态迁移 | 可编程 TMS 序列 | TAP 状态迁移及暂停后恢复正确 | 中 |
| 147 | JTAG | `et_jtag_tap_reset` | 多 TAP 状态下异步 TRSTn | 可控 TRSTn 与 TAP 状态观察 | 异步复位后回到 Test-Logic-Reset | 中 |
| 148 | JTAG | `et_jtag_emureg_sweep` | EMU_REG 地址译码与状态窗口 | JTAG EMU_REG 读写 | 寄存器窗口读值、可写位和恢复值正确 | 高 |
| 149 | JTAG | `et_jtag_emureg_halfword` | EMU_REG 16-bit/high-half 译码 | JTAG READA16/WRITEA16 | 半字别名和高半字访问正确 | 高 |
