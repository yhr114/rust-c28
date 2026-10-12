# FPGA 运行配置建议

## 编译输入

每条 case 目录保持远端 SDK 结构：

```text
case_src/<module>/<case>/
  case.mk
  include/
  src/
```

FPGA 侧可以把对应 case 拷贝回 SDK 的 `example/<case>/` 下，或修改现有 build flow 指向 `case_src/<module>/<case>`。

## Boot / 结束判定

- 建议优先使用 FPGA 已稳定的 boot path。
- 若 case 依赖 PASS/FAIL trap，需要 FPGA 侧能够观察 trap 地址、UART log 或 JTAG status。
- reset/watchdog/LPM case 需要支持 reset 后重新进入应用，不能只看第一次启动。

## 板级连接建议

- SPI/SCI/LIN loopback：优先内部 loopback；若使用外部 loopback，需要确认 pin mux 与 jumper。
- CAN/I2C：需要外部收发器或可控从设备；没有从设备时优先跑寄存器/self-test 类 case。
- GPIO/XINT/TZ：需要可控外部 pulse，或 FPGA 内部 test harness 产生 pulse。
- EPWM/ECAP/HRCAP/EQEP/ADC：建议 ILA 捕获输出波形、输入脉冲、capture 结果、EOC/interrupt。

## 建议执行顺序

1. `Risk=低` 的寄存器/内部 loopback case。
2. `Risk=中` 的中断、复位、pin loopback、ILA 观察 case。
3. 需要外部从设备、特殊时钟或 reset 重入的 case 最后跑。

## JTAG 特别说明

- 10 条 JTAG 条目共用 `case_src/jtag/et_jtag` 目标镜像，不是 10 个独立 C 应用。
- `run_config/et_jtag_selected.list` 中的 `+ET_JTAG_SEQ` 是 EDA/UVM 流程选择参数；FPGA 侧需要由调试器脚本、ATE 或 JTAG 控制器实现同等操作。
- 先确认 38-bit IR、LSB-first、TAP reset、BYPASS 和 IDCODE，再执行 CPU debug 与 EMU_REG 类流程。
- 涉及 TESTMODE、EXTEST、HIGHZ 或可写 EMU_REG 的流程执行后必须恢复默认状态。
