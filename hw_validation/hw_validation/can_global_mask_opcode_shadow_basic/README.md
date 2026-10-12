# can_global_mask_opcode_shadow_basic：28035 实测

## 范围

使用用户的 F28035 + XDS100v1，CCS 20.1.1 scripting、C2000 CGT 22.6.1.LTS、
C2000Ware 26.01.00.00。RAM 下载，未烧写 Flash。

原 main.c 未修改，SHA256：
448BB9E330256A9AEB00208D6494E7E2F2BD22950F714E10BA1E907867E25FE4。

交付包缺少 board_can_case.h、test_runtime 和 CAN helper 实现；原 run_one_template.sh
只有 echo，编译、下载和等待命令全为注释。因此本次验证的是新增的本机自动化流程，
以及原 main.c + 明确补充的 TI 适配层，不是原 s03_sdk 自动化流程。
将 can_case_basic_init(1) 解释为自测试初始化，邮箱常量取 0；这是适配假设。

## 结果和变化

基准运行（关闭 snapshot、中途不设断点）与采样运行均得到 PASS、失败码 0。
以 baseline_results.json / trace_results.json 及对应日志为最终证据。

| 观察阶段 | CANME | CANMD | CANMIM | CANMIL | CANTA | CANRMP | CANTRS |
|---|---|---|---|---|---|---|---|
| 第一次初始化后 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 第一组写入后（第17行前断点） | 1 | 0 | **0，源码写1** | 0 | 0 | 0 | 0 |
| 第二组写入后（第二次初始化入口） | 3 | 2 | **0，源码写3** | 2 | 0 | 0 | 0 |
| 第二次初始化后 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| TX邮箱0配置后 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 发起发送后采样 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| 确认发送后 | 1 | 0 | 0 | 0 | 1 | 1 | 0 |
| 清发送确认后 / PASS | 1 | 0 | 0 | 0 | 0 | 1 | 0 |

初始化后 CANMC=0x2040：SCB=1、STM=1，为 HECC 自测试模式。
MSGID0=0x0CA80000，对应标准 ID 0x32A；MSGCTRL0=4，MDL0=0x0A0B0C0D，MDH0=0。
CANGAM 和 LAM0 在采样阶段均为0，原 main.c 不写入/断言这些字段。
CANRMP 在自测试发送后置位，本例没有清理它；不能由此推断验证了外部 CAN 收发器或连线。
初始化前邮箱 RAM 的值未定义，本适配层显式清零；这些随机值不属于故障。
before_main 的 CAN 外设时钟尚未打开，调试器此时读到的全0不能当作有效硬件复位默认值。

## 发现的问题

1. **CANMIM 写入无效但用例仍 PASS。** CANMIM 受 EALLOW 保护，原 main.c 两次写入前
   没有 EALLOW；本适配层初始化以 EDIS 结束，故实际仍为0。CANMIL=2、CANME=3、CANMD=2
   说明并非所有控制寄存器写入都失败。原程序没有读取并校验这些值，且随后又初始化，
   最终发送通过无法检出这个问题。若原 SDK 泄漏 EALLOW=1，行为可能不同，需核对其实现。
2. **ACKE 检查存在访问宽度问题。** 对 ECanaRegs.CANES.bit.ACKE 的直接访问编译成
   DP=0x180、TBIT @0x19,#3，即访问0x6019高半字。TI eCAN 控制寄存器要求32位访问。
   建议先用32位 MOVL 读入 RAM shadow，再检查 ACKE；通过反汇编确认宽度。
   适配层 CCE 轮询使用 volatile RAM shadow，避免编译器将掩码操作折叠成外设16位访问。
3. **覆盖范围与用例名称/清单不符。** main.c 不验证 CANGAM/LAM/CANOPC 的读回、掩码过滤
   或 shadow 一致性，最终仅判断 TX ACK 与 ACKE。PASS 只说明该路径执行到了通过分支。
4. **CANTA/CANRMP 是写1清除。** 前两组写1/3后读回0符合语义，不能按普通RW寄存器
   要求读回1/3；要验证清除能力，应先产生对应事件再清除并断言。

依据：[TI F2803x TRM，eCAN EALLOW保护与寄存器说明](https://www.ti.com/lit/ug/sprui10/sprui10.pdf)，
以及本机 C2000Ware DSP2803x_ECan.c 中关于32位访问/32位 shadow 的说明。

## 重跑

在本目录执行：

```powershell
.\validate.ps1          # 基准运行
.\validate.ps1 -Trace   # 第17行断点 + 各阶段采样
```

脚本编译并复制原源码到 ASCII 临时目录，连接后复位、下载RAM程序，验证已停在main，
运行至结束，读取 PASS/FAIL 和失败码。异常/FAIL 会抛错，不当作 PASS。
基准运行关闭过程采样以避免采样耗时及断点改变发送时序；采样运行用于观察变化，
snapshot中的各字段是依次读取，并非同一时钟周期的原子快照。

trace[].stage：0开时钟后，1首次初始化前，2首次初始化后，3第二次初始化前，
4第二次初始化后，5邮箱配置后，6发起发送后，7等待确认成功，8清确认后，9 PASS；
70发送等待超时，99 FAIL。0xE001/0xE002是适配层CCE超时；0x6381/0x6382是原用例失败码。

文件：build.ps1 / validate.ps1 / run.js、适配层、case.out/map/dis、两组JSON和运行日志。
