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

static void adc_timer_init(void)
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
    EALLOW;
    AdcRegs.INTSEL1N2.bit.INT1SEL  = 0;
    AdcRegs.INTSEL1N2.bit.INT1E    = 1;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0;
    AdcRegs.ADCSOC0CTL.bit.CHSEL   = 0U;
    AdcRegs.ADCSOC0CTL.bit.ACQPS   = 6U;
    EDIS;
}

static void timer0_start(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR3.bit.CPUTIMER0ENCLK = 1;
    EDIS;
    CpuTimer0Regs.TPR.bit.TDDR   = 0;
    CpuTimer0Regs.TPRH.bit.TDDRH = 0;
    CpuTimer0Regs.PRD.all         = ADC_TRIG_TIMER0_PRD;
    CpuTimer0Regs.TCR.all = 0xC020U;
}

void main(void)
{
    unsigned int timeout;
    volatile unsigned int result;
    board_demo_init();
    adc_timer_init();
    EALLOW;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_TRIGSEL_TIMER0;
    EDIS;
    timer0_start();

    /* STAGE 1: timer queued SOC0? */
    timeout = 0;
    while ((AdcRegs.ADCSOCFLG1.bit.SOC0 == 0U) && (AdcRegs.ADCSOCOVF1.bit.SOC0 == 0U)) {
        if (++timeout >= 60000U)
            test_runtime_fail(ADC_TRIG_TIMER0_FAIL_SOC_NEVER);
    }
    /* Stop timer + clear TIF: de-assert TINT level so ADCTRIG stops; SOC0 already latched */
    CpuTimer0Regs.TCR.all = 0x8010U;

    /* STAGE 3: wait for conversion EOC → ADCINT1 */
    timeout = 0;
    while (!AdcRegs.ADCINTFLG.bit.ADCINT1) {
        if (++timeout >= 50000U)
            test_runtime_fail(ADC_TRIG_TIMER0_FAIL_TIMEOUT_INT1);
    }
    result = AdcResult.ADCRESULT0; (void)result;

    AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1;
    if (AdcRegs.ADCINTFLG.bit.ADCINT1 != 0U)
        test_runtime_fail(ADC_TRIG_TIMER0_FAIL_FLAG_NOT_CLEAR);
    if (AdcRegs.ADCSOCOVF1.bit.SOC0 != 0U)
        test_runtime_fail(ADC_TRIG_TIMER0_FAIL_SOC_OVF);

    board_demo_toggle();
    test_runtime_pass();
}
