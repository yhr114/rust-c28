# FPGA / 真芯片预期结果与对比点

## 通用对比项

- C case 最终 PASS/FAIL。
- 若有 UART/JTAG log，记录 case 名、关键阶段打印、最终 PASS 字符串。
- 关键寄存器 dump：配置寄存器、状态寄存器、interrupt flag、clear 后状态。
- 关键引脚或 ILA：TX/RX、PWM、GPIO、XCLKOUT、reset、interrupt line。

## 模块重点

- LIN：LINMODE/SCIMODE、baud、RXRDY/TXRDY、checksum、break/sync/header、LINRX/LINTX。
- SPI：SPICCR/SPICTL/SPISTS/SPIFFTX/SPIFFRX、SIMO/SOMI/SCLK/STE、TX/RX pattern。
- CAN/eCAN：CANMC/CANES/CANGIF/CANME/CANMD/CANTRS/CANTA/CANRMP、mailbox data、CANTX/CANRX。
- PIE：PIEIFR/PIEIER/PIEACK、vector table、CPU interrupt vector、XINT/TIMER/NMI 路径。
- WDG/SYS：WDCR/WDKEY/SCSR/WDFLAG、reset 后重入、PLL/clock/DIVSEL/XCLKOUT。
- SCI：SCICCR/SCICTL/SCIFFTX/SCIFFRX、TX/RX data、FIFO level、RXRDY/TXRDY。
- GPIO：GPxMUX/GPxDIR/GPxDAT/XINT source、pin toggle/readback。
- EPWM：TBPRD/TBCTR/CMPA/CMPB/AQ/TZ/ET、EPWMxA/B 波形。
- ECAP：CAP1-4、ECCTL1/2、ECFLG/ECEINT、capture 输入脉冲、APWM 输出 period/duty。
- HRCAP：HRCAP counter/result、FIFO/status、HR/normal capture flag、softreset/clock gate、输入 pulse。
- EQEP：QPOSCNT/QEPSTS/QFLG/QEINT、QEPA/QEPB/QEPI、position compare pulse。
- ADC：SOCCTL/RESULT/EOC/ADCINT/overflow、trigger source 和 conversion 完成。
- I2C：I2CMDR/I2CSTR/I2CCNT/I2CDXR/I2CDRR、ACK/NACK/STOP、SCL/SDA。
- JTAG：TAP state、38-bit IR、DR scan、DBGSTAT、CPU run/halt/step/reset、EMU_REG、BYPASS/IDCODE/TESTMODE/EXTEST/HIGHZ。
