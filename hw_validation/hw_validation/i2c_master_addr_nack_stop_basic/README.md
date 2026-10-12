# i2c_master_addr_nack_stop_basic 实板测试

原main.c + TI适配层，F28035 / XDS100v1，CCS 20.1.1 scripting，RAM下载。
最终连续运行和断点观察运行均 PASS，test_status=1、test_fail_code=0，未修改原源码。
源码SHA256：9BFFD8BDD9AA1422F57179B9B73C11CCD8B7CEB3880A9112E08B2837408F2CF3。

## 配置

TI InitSysCtrl配置名义60MHz；GPIO28=SDA、GPIO29=SCL，异步输入，启用内部上拉。
I2C非FIFO、轮询模式；自身地址0x30，目标7位地址0x36，待发数据0x3C，长度1。
使用原case_config.h的PSC=6、CLKL=200、CLKH=160、WAIT_LOOPS=250000。
本次未模拟VIP从机，观察当前实际总线产生的NACK；没有使用示波器/逻辑分析仪。

## 原代码逻辑

1. board_demo_init / i2c_case_i2ca_init。
2. 先检查上次STOP是否结束（STP）及总线忙状态（BB）。
3. 写I2CSAR/I2CCNT，清状态标志，预装0x3C到I2CDXR。
4. 写I2CMDR=0x6E20，启动主机发送，预置STOP。
5. 轮询：仲裁丢失返回错误；NACK则清NACK、置STP并等待STOP；需要时继续装数据。
6. 未检测到NACK却出现SCD则返回UNEXPECTED_ACK=6，main报0x8326。
7. 收到NACK后，若SCD=1，清SCD并返回OK；或STP=0且BB=0也返回OK。
8. status=OK则PASS，否则报0x8320+status。

## 实测

| 阶段 | I2CSTR | I2CMDR | I2CCNT | 解释 |
|---|---|---|---|---|
| 初始化后 | 0x0410 | 0x4020 | — | BB=0，模块已启用 |
| 第56行，清NACK前 | 0x1406 | 0x4620 | 1 | NACK=1，确实进入NACK分支 |
| 第11行，清SCD前 | 0x0420 | 0x4220 | 1 | SCD=1、BB=0、STP=0 |
| 连续运行的结束采样 | 0x0400 | 0x4E20 | 1 | 程序已PASS、BB=0，但STP尚为1 |
| 稍后调试器读取 | 0x0400 | 0x4220 | 1 | STP已自行清零、BB=0 |

断点运行结束采样已经是0x4220。断点改变了观测时刻，不用于证明总线实时波形。
GPIO28/29均读为高。I2CCNT仍为1与数据未完成传输相符；程序本身只判断NACK，
不能严格区分地址NACK与数据NACK。严格的地址阶段证明需要受控从机或总线波形。

## 注意点

- 该用例是“预期NACK”的负向测试，NACK在这里属于成功条件，不是失败。
- 第10至12行一看到SCD就立即返回，不保证返回同一瞬间STP已清零。
  TI手册说明STP清除会延后至SCD置位，实测随后确实清零，不能据早期采样判断卡死。
  连续发起下一笔事务前应有界等待STP=0且BB=0；本函数入口目前只检查一次，
  紧接着复用可能遇到STP_BUSY（本次未执行第二笔连续事务）。
- 超时分支置STP后直接返回，没有进一步等待清理；批量跑用例时宜在失败后复位I2C。
- 只识别NACK标志，没有明确检查NACK发生在地址阶段；与VIP配合时这一前提由VIP保证。

依据：[TI F2803x TRM](https://www.ti.com/lit/ug/sprui10/sprui10.pdf)，I2C STP/SCD说明。

## 自动化

运行 `./validate.ps1`。输出 run.log / results.json；编译结果 case.out / case.map。
脚本先连续运行，再在原main.c第56行（NACK）与第11行（SCD）断点采样。
除原case PASS外，脚本还确认稍后STP=0且BB=0；不把瞬态STP=1当作永久失败。
initial_* / stop_timing_diagnosis.*保留早期诊断：当时额外断言要求立即STP=0，
因瞬态时序退出1；原C用例始终是PASS。最终证据请看run.log/results.json。

本适配层状态编码：OK=0、TIMEOUT=1、STP_BUSY=2、BUS_BUSY=3、ARB_LOST=4；
UNEXPECTED_ACK=6由原main.c定义。成功结果不受未知原公共头文件状态编码影响。
