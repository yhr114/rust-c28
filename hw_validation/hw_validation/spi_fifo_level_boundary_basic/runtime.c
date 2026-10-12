#include "DSP28x_Project.h"

volatile unsigned short validation_mode = 0;
volatile unsigned short test_status = 0;
volatile unsigned long test_fail_code = 0;
volatile unsigned short saved_spiccr, saved_spictl, saved_spists;
volatile unsigned short saved_spifftx, saved_spiffrx, saved_spidat;

void device_sdk_init(void)
{
    DINT;
    IER = 0;
    IFR = 0;
    /* Minimal adapter: keep reset clock setup; enable only SPI-A, disable WD.
       The original device_sdk_init implementation was not delivered. */
    EALLOW;
    SysCtrlRegs.WDCR = 0x0068;
    SysCtrlRegs.PCLKCR0.bit.SPIAENCLK = 1;
    EDIS;
    test_status = 0;
    test_fail_code = 0;
    if (validation_mode == 1) {
        /* Controlled additional run: 16-bit internal loopback master. */
        SpiaRegs.SPICCR.all = 0x001F;
        SpiaRegs.SPICTL.all = 0x0006;
        SpiaRegs.SPIBRR = 0x007F;
        SpiaRegs.SPIFFTX.all = 0xC040;
        SpiaRegs.SPIFFRX.all = 0x2040;
        SpiaRegs.SPIFFCT.all = 0;
        SpiaRegs.SPICCR.all = 0x009F;
    }
}

void capture_result(void)
{
    saved_spiccr = SpiaRegs.SPICCR.all;
    saved_spictl = SpiaRegs.SPICTL.all;
    saved_spists = SpiaRegs.SPISTS.all;
    saved_spifftx = SpiaRegs.SPIFFTX.all;
    saved_spiffrx = SpiaRegs.SPIFFRX.all;
    saved_spidat = SpiaRegs.SPIDAT;
    asm(" ESTOP0");
    for (;;) { }
}

void test_runtime_pass(void)
{
    test_status = 1;
    capture_result();
}

void test_runtime_fail(unsigned long code)
{
    test_fail_code = code;
    test_status = 2;
    capture_result();
}
