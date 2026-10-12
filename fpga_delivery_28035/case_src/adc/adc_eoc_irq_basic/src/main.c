#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for adc_eoc_irq_basic
#endif

#define ADC_SOC0_CHANNEL_B5          13U
#define ADC_SOC_TRIGGER_SOFTWARE     0U

static void adc_init(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR0.bit.ADCENCLK = 1;
    AdcRegs.ADCCTL1.bit.RESET = 1;
    EDIS;

    asm(" NOP");
    asm(" NOP");

    EALLOW;
    AdcRegs.ADCCTL2.bit.CLKDIV2EN = 1;
    AdcRegs.ADCCTL1.bit.INTPULSEPOS = 1;
    AdcRegs.ADCCTL1.bit.ADCREFSEL = 0;
    AdcRegs.ADCCTL1.bit.ADCREFPWD = 1;
    AdcRegs.ADCCTL1.bit.ADCBGPWD = 1;
    AdcRegs.ADCCTL1.bit.ADCPWDN = 1;
    AdcRegs.ADCCTL1.bit.ADCENABLE = 1;
    EDIS;

    board_delay_us(ADC_EOC_IRQ_BASIC_POWERUP_DELAY_US);

    EALLOW;
    /* ADCINT1 triggered by EOC0, non-continuous mode */
    AdcRegs.INTSEL1N2.bit.INT1SEL = 0;
    AdcRegs.INTSEL1N2.bit.INT1E = 1;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0;

    AdcRegs.ADCSOC0CTL.bit.CHSEL  = ADC_SOC0_CHANNEL_B5;
    AdcRegs.ADCSOC0CTL.bit.ACQPS  = ADC_EOC_IRQ_BASIC_ACQPS;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_SOC_TRIGGER_SOFTWARE;
    EDIS;
}

void main(void)
{
    unsigned int timeout;
    volatile unsigned int result;

    board_demo_init();
    adc_init();

    /* software force SOC0 */
    AdcRegs.ADCSOCFRC1.bit.SOC0 = 1;

    /* poll ADCINT1 flag */
    timeout = 0;
    while (!AdcRegs.ADCINTFLG.bit.ADCINT1) {
        if (++timeout >= ADC_EOC_IRQ_BASIC_POLL_TIMEOUT) {
            test_runtime_fail(ADC_EOC_IRQ_BASIC_FAIL_TIMEOUT_INT1);
        }
    }

    /* read result (value is model-dependent; just verify readable) */
    result = AdcResult.ADCRESULT0;
    (void)result;

    /* clear ADCINT1 flag */
    AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1;
    if (AdcRegs.ADCINTFLG.bit.ADCINT1 != 0U) {
        test_runtime_fail(ADC_EOC_IRQ_BASIC_FAIL_FLAG_NOT_CLEAR);
    }

    /* SOC0 overflow must not have fired */
    if (AdcRegs.ADCSOCOVF1.bit.SOC0 != 0U) {
        test_runtime_fail(ADC_EOC_IRQ_BASIC_FAIL_SOC_OVF);
    }

    board_demo_toggle();
    test_runtime_pass();
}
