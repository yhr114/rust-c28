# gpio_toggle_basic 实板测试

结果：**PASS**。F28035 + XDS100v1，CCS 20.1.1 scripting，RAM下载运行。

原 main.c 保持不变。公共 board_gpio_case.h、board_demo_init、GPIO辅助函数和
test_runtime 未包含在交付包中，本目录提供 TI C2000Ware 适配实现，不能等同于原 SDK 全环境验证。
原源码 SHA256：96E2880E64E08DEEC29803AE1C54A1B5D8F3E813C5D9540D776FEC4CA1CC0483。

- test_status=1，test_fail_code=0。
- GPIO34翻转次数=8。
- 读取初始状态以及每次延时后的状态：`0,1,0,1,0,1,0,1,0`。
- 最终 GPBDAT=0x1CCB，GPIO34对应bit2=0。
- GPBDIR=0x4，GPIO34为输出；GPBMUX1=0，GPIO功能。
- 测试程序停在结束标记 ESTOP0（本次PC=0x81BC）。

适配层使用 TI InitSysCtrl，名义60MHz，DSP28x_usDelay实现名义100us延时。
该结果验证软件可见GPIO状态，未使用示波器测量脉宽/边沿。每次采样及函数调用也有额外耗时。
只有bit2是本用例的目标，GPBDAT其他位不是本用例的验证结论。

执行 `./validate.ps1` 可重跑编译、连接、复位、RAM下载、执行和结果采集。
脚本同时检查用例状态和9个状态采样，异常/FAIL/序列不符会报错。
已处理CCS下载后自动停在main的行为，不会额外运行一次才开始测试。
输出位于 run.log、results.json；case.out/map为本次编译结果。
