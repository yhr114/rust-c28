# ET/JTAG 10 条 case 预期结果

| Case | 关键预期结果 |
|---|---|
| `et_jtag_example` | CPU 能 halt/run/step；变量 `a` 可读写；PC/AU0 breakpoint 流程完成 |
| `et_jtag_cmd_flow` | rude/polite halt、run、step、FreeRun、RT enable/disable 后 DBGSTAT 与 CPU 状态一致 |
| `et_jtag_reset_nbstep` | SET_RESET/RESET_STEP 能产生 CPU reset、nb_step 和 clr_step 预期行为 |
| `et_jtag_mem16_dbgstat` | READA16/WRITEA16 只更新目标半字，DBGSTAT 可正确读取 |
| `et_jtag_tap_dr_sweep` | BYPASS、IDCODE、TESTMODE、DC_STRBS、DIR 的 DR 长度、选择和 TDO 返回正确 |
| `et_jtag_tap_highz_bscan` | PRELOAD/EXTEST/HIGHZ 选择正确，BSR shift 与 pad 高阻行为可观察 |
| `et_jtag_tap_pause` | Pause-DR/Pause-IR/Exit2 状态跳转正确，恢复 shift/update 后数据不乱 |
| `et_jtag_tap_reset` | 在 Capture/Exit/Pause 等状态拉低 TRSTn 后均回到 Test-Logic-Reset |
| `et_jtag_emureg_sweep` | EMU_REG decode、只读值、可写位及副作用寄存器恢复符合设计 |
| `et_jtag_emureg_halfword` | 16-bit low/high-half 访问和 alias decode 正确，不破坏另一半字 |
