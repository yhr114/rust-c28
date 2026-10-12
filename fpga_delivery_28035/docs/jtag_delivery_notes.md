# ET/JTAG FPGA 交付说明

## 来源

- SDK 分支：`s03_sdk origin/et_jtag`，commit `5828f47ce5c9cf66c4e2831ef0616dd244828ad7`。
- 验证分支：`s03_verify origin/et_jtag`，commit `2873f42643cf42e24382d8680fff5822a44354bd`。
- 目标程序：`case_src/jtag/et_jtag`。
- 原始流程参考：`docs/jtag_et_jtag_branch`。

## 交付模型

这 10 条 case 是 10 套 JTAG 主机操作流程，均加载同一个 `et_jtag` C 镜像。目标程序初始化系统后持续递增全局变量 `a`，用于观察 run、halt、step 和 memory access。EDA 环境通过 `+ET_JTAG_SEQ=<flow>` 选择流程；FPGA 环境需要把相同流程移植到调试器脚本、ATE 或板级 JTAG 控制器。

## 推荐顺序

1. `et_jtag_tap_reset`
2. `et_jtag_tap_pause`
3. `et_jtag_tap_dr_sweep`
4. `et_jtag_cmd_flow`
5. `et_jtag_mem16_dbgstat`
6. `et_jtag_example`
7. `et_jtag_reset_nbstep`
8. `et_jtag_emureg_halfword`
9. `et_jtag_emureg_sweep`
10. `et_jtag_tap_highz_bscan`

`et_jtag_tap_highz_bscan` 会改变 pad/BSR 状态，建议最后执行并在结束后复位 TAP 和芯片。
