# SPI FIFO 判据修订版

修改版 main.c 已在 F28035 + XDS100v1 上 RAM 运行，两种适配层初始条件均 PASS。
按用户最新要求，修改版单独保存为工作区根目录 spi_fifo_level_boundary_basic_fixed.c。
交付目录 case_src/spi/spi_fifo_level_boundary_basic/src/main.c 已恢复原版；
同目录 main.c.bak_before_fifo_fix 和本目录 main_original.c 也保留原版副本。
build.ps1 编译根目录的 spi_fifo_level_boundary_basic_fixed.c（暂存时命名为main.c）；
本目录 main.c 为相同内容的修订版参考副本。

修改内容：

- 显式配置16位SPI主机内部回环，不依赖公共初始化留下的SPI状态。
- 先保持FIFO复位，再释放复位，检查初始TX/RX为空。
- 删除“写一个字后立即要求TXFFST非零”的断言。
- 逐字写入4个数据，每次有界等待RXFFST达到预期，保留接收数据以检查0到4的计数变化。
- 按顺序读回全部数据，检查计数4到0；检查数据、RX无溢出、TX最终为空。

这是 TX 排空 + RX FIFO 空/单字/满/出队边界测试，不宣称覆盖 TX FIFO 填满边界、
外部引脚时序或FIFO中断行为。要验证TX填满，应另建能控制出队的测试条件。
F28035 SPI FIFO深度为4；其他芯片需按手册调整。

实际结果：

```
status=PASS, fail_code=0
RXFFST: 0,1,2,3,4,3,2,1,0
received: 0x0011,0xA55A,0x5AA5,0x1234
SPIFFTX=0xE080 (TXFFST=0)
SPIFFRX=0x2084 (RXFFST=0, RXFFINT仍为1；本例未验证/清除此标志)
```

最终TXFFST仍是0，但这次是接收完成后预期的排空状态，所以通过。
run.log / results.json 保存两种初始条件的实测结果。
运行 ./validate.ps1 可重跑构建和两种初始条件，报错/FAIL会返回失败。

新失败码：0x533101配置、0x533102发送排空超时、0x533110附近计数错误、
0x533120附近接收等待超时、0x533130附近数据错误、0x533140接收溢出。

依据：[TI 2802x/2803x SPI手册](https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/171/2352.SPI.pdf)。
