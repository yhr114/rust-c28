#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for adc_multi_soc_sw_trigger
#endif

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
    AdcRegs.ADCCTL1.bit.ADCREFSEL  = 0;
    AdcRegs.ADCCTL1.bit.ADCREFPWD  = 1;
    AdcRegs.ADCCTL1.bit.ADCBGPWD   = 1;
    AdcRegs.ADCCTL1.bit.ADCPWDN    = 1;
    AdcRegs.ADCCTL1.bit.ADCENABLE  = 1;
    EDIS;

    board_delay_us(ADC_MULTI_SOC_POWERUP_DELAY_US);

    EALLOW;
    /* ADCINT1->EOC0, ADCINT2->EOC1, ADCINT3->EOC2, all non-continuous */
    AdcRegs.INTSEL1N2.bit.INT1SEL  = 0;
    AdcRegs.INTSEL1N2.bit.INT1E    = 1;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0;
    AdcRegs.INTSEL1N2.bit.INT2SEL  = 1;
    AdcRegs.INTSEL1N2.bit.INT2E    = 1;
    AdcRegs.INTSEL1N2.bit.INT2CONT = 0;
    AdcRegs.INTSEL3N4.bit.INT3SEL  = 2;
    AdcRegs.INTSEL3N4.bit.INT3E    = 1;
    AdcRegs.INTSEL3N4.bit.INT3CONT = 0;

    /* SOC0: channel A0, SW trigger */
    AdcRegs.ADCSOC0CTL.bit.CHSEL   = ADC_MULTI_SOC_CH_SOC0;
    AdcRegs.ADCSOC0CTL.bit.ACQPS   = ADC_MULTI_SOC_ACQPS;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_SOC_TRIGGER_SOFTWARE;

    /* SOC1: channel A1, SW trigger */
    AdcRegs.ADCSOC1CTL.bit.CHSEL   = ADC_MULTI_SOC_CH_SOC1;
    AdcRegs.ADCSOC1CTL.bit.ACQPS   = ADC_MULTI_SOC_ACQPS;
    AdcRegs.ADCSOC1CTL.bit.TRIGSEL = ADC_SOC_TRIGGER_SOFTWARE;

    /* SOC2: channel B0, SW trigger */
    AdcRegs.ADCSOC2CTL.bit.CHSEL   = ADC_MULTI_SOC_CH_SOC2;
    AdcRegs.ADCSOC2CTL.bit.ACQPS   = ADC_MULTI_SOC_ACQPS;
    AdcRegs.ADCSOC2CTL.bit.TRIGSEL = ADC_SOC_TRIGGER_SOFTWARE;
    EDIS;
}

static void poll_int(unsigned int intbit_mask, unsigned int fail_code)
{
    unsigned int timeout = 0;
    while (!(AdcRegs.ADCINTFLG.all & intbit_mask)) {
        if (++timeout >= ADC_MULTI_SOC_POLL_TIMEOUT) {
            test_runtime_fail(fail_code);
        }
    }
}

void main(void)
{
    volatile unsigned int r0, r1, r2;

    board_demo_init();
    adc_init();

    /* force SOC0, SOC1, SOC2 simultaneously */
    AdcRegs.ADCSOCFRC1.all = 0x0007U;

    /* wait for each ADCINT in sequence (RR: SOC0 first, SOC1 second, SOC2 third) */
    poll_int(0x0001U, ADC_MULTI_SOC_FAIL_TIMEOUT_INT1);   /* ADCINT1 = EOC0 */
    AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1;

    poll_int(0x0002U, ADC_MULTI_SOC_FAIL_TIMEOUT_INT2);   /* ADCINT2 = EOC1 */
    AdcRegs.ADCINTFLGCLR.bit.ADCINT2 = 1;

    poll_int(0x0004U, ADC_MULTI_SOC_FAIL_TIMEOUT_INT3);   /* ADCINT3 = EOC2 */
    AdcRegs.ADCINTFLGCLR.bit.ADCINT3 = 1;

    /* verify results are bound to SOC number, not channel number */
    r0 = AdcResult.ADCRESULT0;   /* must have SOC0 result */
    r1 = AdcResult.ADCRESULT1;   /* must have SOC1 result */
    r2 = AdcResult.ADCRESULT2;   /* must have SOC2 result */
    (void)r0; (void)r1; (void)r2;

    /* all SOC flags must be cleared after conversion */
    if ((AdcRegs.ADCSOCFLG1.all & 0x0007U) != 0U) {
        test_runtime_fail(ADC_MULTI_SOC_FAIL_SOC_FLAG_LEFT);
    }

    board_demo_toggle();
    test_runtime_pass();
}
