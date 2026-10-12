#include "board_gpio_case.h"
#include "test_runtime.h"
/* Replacement for missing original SDK helpers. */
volatile unsigned short test_status=0, toggle_count=0, sample_count=0;
volatile unsigned short samples[9];
volatile unsigned long test_fail_code=0, final_dat=0, final_dir=0, final_mux=0;
void board_demo_init(void)
{
    DINT; IER=0; IFR=0;
    InitSysCtrl(); /* TI internal oscillator + PLL: nominal SYSCLK=60 MHz. */
}
void gpio_case_gpio34_output_init(unsigned int level)
{
    EALLOW;
    GpioCtrlRegs.GPBMUX1.bit.GPIO34=0;
    if(level) GpioDataRegs.GPBSET.all=4UL;
    else GpioDataRegs.GPBCLEAR.all=4UL;
    GpioCtrlRegs.GPBDIR.bit.GPIO34=1;
    EDIS;
    /* Allow the input readback path to settle. */
    DSP28x_usDelay(10UL);
    samples[sample_count++]=(GpioDataRegs.GPBDAT.all>>2)&1UL;
}
void gpio_case_gpio34_toggle(void)
{
    GpioDataRegs.GPBTOGGLE.all=4UL;
    toggle_count++;
}
void board_delay_us(unsigned long us)
{
    /* TI delay loop takes 5 cycles/iteration + 9 cycles overhead.
       For 60 MHz: floor((60*us-9)/5) = 12*us-2 for integer us>=1. */
    if(us) DSP28x_usDelay(us*12UL-2UL);
    if(sample_count<9) samples[sample_count++]=(GpioDataRegs.GPBDAT.all>>2)&1UL;
}
unsigned int gpio_case_gpio34_read(void)
{
    return (unsigned int)((GpioDataRegs.GPBDAT.all>>2)&1UL);
}
void test_done(void)
{
    final_dat=GpioDataRegs.GPBDAT.all;
    final_dir=GpioCtrlRegs.GPBDIR.all;
    final_mux=GpioCtrlRegs.GPBMUX1.all;
    asm(" ESTOP0");
    for(;;) {}
}
void test_runtime_pass(void) {test_status=1;test_done();}
void test_runtime_fail(unsigned long c) {test_fail_code=c;test_status=2;test_done();}
