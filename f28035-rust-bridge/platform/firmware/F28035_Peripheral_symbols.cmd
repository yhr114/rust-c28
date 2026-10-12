/*
 * EABI-safe aliases for the peripheral register structures used by the
 * Rust control firmware.  The legacy GlobalVariableDefs.c definitions place
 * these objects in named sections; modern EABI then emits zero-initialization
 * records for those sections and _c_int00 writes into live peripherals.
 *
 * Absolute symbols preserve the TI header field layouts without creating any
 * storage or C initialization records.
 */
AdcResult     = 0x00000B00;
AdcRegs       = 0x00007100;
CpuTimer0Regs = 0x00000C00;
PieCtrlRegs   = 0x00000CE0;
PieVectTable  = 0x00000D00;
EPwm1Regs     = 0x00006800;
GpioCtrlRegs  = 0x00006F80;
GpioDataRegs  = 0x00006FC0;
GpioIntRegs   = 0x00006FE0;
SysCtrlRegs   = 0x00007010;
FlashRegs     = 0x00000A80;
XIntruptRegs  = 0x00007070;

/* M1 SPI (SpibRegs = SPI-B register block, 0x7740) */
SpibRegs      = 0x00007740;

/* M2 I2C (I2caRegs = I2C-A register block, 0x7900) */
I2caRegs      = 0x00007900;

/* M3 LIN (LinaRegs = LIN-A register block, 0x6C00) */
LinaRegs      = 0x00006C00;

/* M4 SCI (SciaRegs = SCI-A register block, 0x7050) */
SciaRegs      = 0x00007050;

/* M5 eCAP (ECap1Regs = Enhanced Capture 1, 0x6A00) */
ECap1Regs     = 0x00006A00;

/* M6 eQEP (EQep1Regs = Enhanced QEP 1, 0x6B00) */
EQep1Regs     = 0x00006B00;

/* M7 HRCAP (HRCap1/2 = High Resolution Capture, 0x6AC0 / 0x6AE0) */
HRCap1Regs    = 0x00006AC0;
HRCap2Regs    = 0x00006AE0;

/* M11 eCAN (ECanaRegs = eCAN-A control, 0x6000; mailboxes 0x6100) */
ECanaRegs     = 0x00006000;
ECanaMboxes   = 0x00006100;
