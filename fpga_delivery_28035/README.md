# 28035 FPGA 对比验证交付包

本目录用于交付给 FPGA/板级验证同事，选择一批适合在 FPGA 与 TI 28035 真实芯片上做行为对比的 C case 和 JTAG 调试流程。

## 当前版本

- 来源远端：`work_0724/s03_sdk` 与 `work_0724/s03_verify` 的 `origin/et_jtag`
- 刷新时间：2026-09-03
- case 总数：149
- 模块总数：15
- 新增覆盖：`JTAG`（10 条 ET/JTAG 逻辑 case）

## 目录

```text
case_src/<module>/<case>/   # SDK 目标程序源码；JTAG 的 10 条流程共用 case_src/jtag/et_jtag
fpga_case_list.csv          # 机器可读清单
fpga_case_list.md           # 人可读清单
docs/package_manifest.json  # 模块和 case manifest
docs/fpga_issue_eda_fpga_classification.md # FPGA/EDA/case 问题归因
docs/missing_cases.txt      # 缺失 case 检查结果
expected_result/            # FPGA/真芯片对比观察点
run_config/                 # 运行建议
scripts/                    # 单 case 运行模板
```

## 使用建议

优先从 `Risk=低` 的寄存器读写、内部 loopback、纯 C 自检 case 开始，再跑 `Risk=中` 的中断、复位、外部 pin/ILA 观察 case。

FPGA 侧可以把 `case_src/<module>/<case>` 拷贝到 SDK 的 `example/<case>`，或让 build flow 直接指向该目录。

JTAG 条目不是 10 个独立 C 程序，而是 `et_jtag` 目标镜像配合 10 套外部 JTAG 操作流程。执行前请先看 `docs/jtag_delivery_notes.md`。
