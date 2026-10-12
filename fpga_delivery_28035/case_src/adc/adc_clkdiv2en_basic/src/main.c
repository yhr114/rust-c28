#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device
#endif

static void adc_base_init(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR0.bit.ADCENCLK = 1;
    AdcRegs.ADCCTL1.bit.RESET = 1;
    EDIS;
    asm(" NOP"); asm(" NOP");
    EALLOW;
    AdcRegs.ADCCTL2.bit.CLKDIV2EN   = 1;
    AdcRegs.ADCCTL1.bit.INTPULSEPOS = 1;
    AdcRegs.ADCCTL1.bit.ADCREFPWD   = 1;
    AdcRegs.ADCCTL1.bit.ADCBGPWD    = 1;
    AdcRegs.ADCCTL1.bit.ADCPWDN     = 1;
    AdcRegs.ADCCTL1.bit.ADCENABLE   = 1;
    EDIS;
    board_delay_us(1000UL);
}
static void adc_soc0_sw(unsigned int chsel)
{
    EALLOW;
    AdcRegs.INTSEL1N2.bit.INT1SEL  = 0;
    AdcRegs.INTSEL1N2.bit.INT1E    = 1;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0;
    AdcRegs.ADCSOC0CTL.bit.CHSEL   = chsel;
    AdcRegs.ADCSOC0CTL.bit.ACQPS   = 6U;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = 0U;
    EDIS;
}
static unsigned int poll_int1(unsigned int timeout_max)
{
    unsigned int t = 0;
    while (!AdcRegs.ADCINTFLG.bit.ADCINT1) {
        if (++t >= timeout_max) return 0U;
    }
    return 1U;
}

void main(void)
{
    volatile unsigned int r;
    board_demo_init();
    /* Explicit CLKDIV2EN=1 with SW-only trigger: no CDC issue */
    adc_base_init();
    adc_soc0_sw(0U);

    AdcRegs.ADCSOCFRC1.bit.SOC0 = 1;
    if (!poll_int1(ADC_CLKDIV2_POLL)) test_runtime_fail(ADC_CLKDIV2_FAIL);
    r = AdcResult.ADCRESULT0; (void)r;
    AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1;

    board_demo_toggle();
    test_runtime_pass();
}
