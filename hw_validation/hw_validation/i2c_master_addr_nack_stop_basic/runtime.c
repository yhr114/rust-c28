#include "board_i2c_case.h"
#include "test_runtime.h"
volatile Uint16 test_status=0;
volatile unsigned long test_fail_code=0;
volatile Uint16 init_str=0, init_mdr=0, final_str=0, final_mdr=0, final_cnt=0, final_sar=0;
volatile unsigned long init_gpio=0, final_gpio=0;
void board_demo_init(void)
{
    DINT; IER=0; IFR=0;
    InitSysCtrl();
}
void board_delay_us(unsigned long us)
{
    if(us) DSP28x_usDelay(us*12UL-2UL);
}
void i2c_case_i2ca_init(Uint16 own, Uint16 prescaler, Uint16 low, Uint16 high)
{
    EALLOW;
    SysCtrlRegs.PCLKCR0.bit.I2CAENCLK=1;
    GpioCtrlRegs.GPAPUD.bit.GPIO28=0;
    GpioCtrlRegs.GPAPUD.bit.GPIO29=0;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO28=3;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO29=3;
    GpioCtrlRegs.GPAMUX2.bit.GPIO28=2;
    GpioCtrlRegs.GPAMUX2.bit.GPIO29=2;
    EDIS;
    I2caRegs.I2CMDR.all=0;
    I2caRegs.I2CIER.all=0;
    I2caRegs.I2CPSC.all=prescaler;
    I2caRegs.I2CCLKL=low;
    I2caRegs.I2CCLKH=high;
    I2caRegs.I2COAR=own;
    I2caRegs.I2CEMDR.all=0;
    I2caRegs.I2CFFTX.all=0;
    I2caRegs.I2CFFRX.all=0;
    I2caRegs.I2CCNT=0;
    I2caRegs.I2CSTR.all=0x0027U;
    I2caRegs.I2CMDR.all=I2C_CASE_MDR_IRS | I2C_CASE_MDR_FREE;
    init_str=I2caRegs.I2CSTR.all;
    init_mdr=I2caRegs.I2CMDR.all;
    init_gpio=GpioDataRegs.GPADAT.all;
}
void test_done(void)
{
    final_str=I2caRegs.I2CSTR.all;
    final_mdr=I2caRegs.I2CMDR.all;
    final_cnt=I2caRegs.I2CCNT;
    final_sar=I2caRegs.I2CSAR;
    final_gpio=GpioDataRegs.GPADAT.all;
    asm(" ESTOP0"); for(;;) {}
}
void test_runtime_pass(void){test_status=1;test_done();}
void test_runtime_fail(unsigned long code){test_fail_code=code;test_status=2;test_done();}
