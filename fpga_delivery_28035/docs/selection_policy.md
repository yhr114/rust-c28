# 选型原则

## 优先选择

- 内部 loopback：例如 SPI/SCI/LIN loopback，便于 FPGA 与真实芯片做数据一致性对比。
- 纯 C 寄存器自检：不依赖 UVM VIP/TB force，最容易移植到 FPGA。
- 中断/PIE/WDG/SYS：可以通过 PASS trap、flag、reset 后重入、ILA 观察做明确判定。
- 引脚可观测 case：GPIO、EPWM、XCLKOUT、TZ/XINT 等，适合 FPGA ILA 或板级探针。

## 暂不优先选择

- 明确依赖 Synopsys VIP 的 case，例如 `*_vip_*`。
- 依赖 TB force/backdoor 的覆盖率 closure case，例如 `*_tb_*`、`*_force_*`、纯 coverage matrix case。
- 需要复杂外设 bus model 的异常注入 case，除非 FPGA 板级环境已经支持对应激励。

## 分级

- 低：纯 C 或内部 loopback，第一批可跑。
- 中：需要 ILA、外部 pin loopback、中断/复位观察。
- 高：需要外部错误注入、可控从设备、特殊时钟/低功耗/板级连线。
