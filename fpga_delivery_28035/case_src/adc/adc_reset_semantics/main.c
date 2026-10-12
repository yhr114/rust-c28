#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "adc_reset_semantics only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_reset_before_adcctl1;
volatile Uint16 g_reset_after_adcctl1;
volatile Uint16 g_reset_before_adcctl2;
volatile Uint16 g_reset_after_adcctl2;
volatile Uint16 g_reset_before_socprictl;
volatile Uint16 g_reset_after_socprictl;
volatile Uint16 g_reset_before_samplemode;
volatile Uint16 g_reset_after_samplemode;
volatile Uint16 g_reset_before_intsocsel1;
volatile Uint16 g_reset_after_intsocsel1;
volatile Uint16 g_reset_before_intsocsel2;
volatile Uint16 g_reset_after_intsocsel2;
volatile Uint16 g_reset_before_soc0ctl;
volatile Uint16 g_reset_after_soc0ctl;
volatile Uint16 g_reset_intflag_before_reset;
volatile Uint16 g_reset_intflag_after_reset;
volatile Uint16 g_reset_socflg_before_reset;
volatile Uint16 g_reset_socovf_before_reset;
volatile Uint16 g_reset_socflg_after_reset;
volatile Uint16 g_reset_socovf_after_reset;

static void adc_apply_reference_config(void)
{
    EALLOW;
    AdcRegs.ADCCTL1.all = 0U;
    AdcRegs.ADCCTL2.all = 0U;

    AdcRegs.ADCCTL1.bit.ADCREFSEL = 0U;
    AdcRegs.ADCCTL1.bit.ADCPWDN = 1U;
    AdcRegs.ADCCTL1.bit.ADCBGPWD = 1U;
    AdcRegs.ADCCTL1.bit.ADCREFPWD = 1U;
    AdcRegs.ADCCTL1.bit.ADCENABLE = 1U;
    AdcRegs.ADCCTL1.bit.INTPULSEPOS = 1U;

    AdcRegs.ADCCTL2.bit.CLKDIV2EN = 0U;
    AdcRegs.ADCCTL2.bit.ADCNONOVERLAP = 0U;

    AdcRegs.SOCPRICTL.all = ADC_RESET_SOCPRICTL_VALUE;
    AdcRegs.ADCSAMPLEMODE.all = ADC_RESET_SAMPLEMODE_VALUE;
    AdcRegs.ADCINTSOCSEL1.all = ADC_RESET_INTSOCSEL1_VALUE;
    AdcRegs.ADCINTSOCSEL2.all = ADC_RESET_INTSOCSEL2_VALUE;

    AdcRegs.ADCSOC0CTL.all = 0U;
    AdcRegs.ADCSOC0CTL.bit.CHSEL = ADC_RESET_SOC0_CHSEL;
    AdcRegs.ADCSOC0CTL.bit.ACQPS = ADC_RESET_SOC0_ACQPS;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_RESET_SOC0_TRIGSEL;

    AdcRegs.INTSEL1N2.all = 0U;
    AdcRegs.INTSEL1N2.bit.INT1SEL = 0U;
    AdcRegs.INTSEL1N2.bit.INT1E = 1U;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0U;

    AdcRegs.ADCINTFLGCLR.all = 0x01FFU;
    AdcRegs.ADCINTOVFCLR.all = 0x01FFU;
    AdcRegs.ADCSOCOVFCLR1.all = 0xFFFFU;
    EDIS;
}

static void adc_init_case(void)
{
    InitAdc();
    AdcOffsetSelfCal();
    adc_apply_reference_config();
    board_delay_us(ADC_RESET_POWERUP_DELAY_US);
}

static Uint32 adc_wait_int1(void)
{
    Uint32 timeout = ADC_RESET_TIMEOUT_LOOPS;

    while (timeout > 0UL) {
        if (AdcRegs.ADCINTFLG.bit.ADCINT1 != 0U) {
            break;
        }
        timeout--;
    }

    return timeout;
}

static void adc_capture_config_before(void)
{
    g_reset_before_adcctl1 = AdcRegs.ADCCTL1.all;
    g_reset_before_adcctl2 = AdcRegs.ADCCTL2.all;
    g_reset_before_socprictl = AdcRegs.SOCPRICTL.all;
    g_reset_before_samplemode = AdcRegs.ADCSAMPLEMODE.all;
    g_reset_before_intsocsel1 = AdcRegs.ADCINTSOCSEL1.all;
    g_reset_before_intsocsel2 = AdcRegs.ADCINTSOCSEL2.all;
    g_reset_before_soc0ctl = AdcRegs.ADCSOC0CTL.all;
}

static void adc_capture_config_after(void)
{
    g_reset_after_adcctl1 = AdcRegs.ADCCTL1.all;
    g_reset_after_adcctl2 = AdcRegs.ADCCTL2.all;
    g_reset_after_socprictl = AdcRegs.SOCPRICTL.all;
    g_reset_after_samplemode = AdcRegs.ADCSAMPLEMODE.all;
    g_reset_after_intsocsel1 = AdcRegs.ADCINTSOCSEL1.all;
    g_reset_after_intsocsel2 = AdcRegs.ADCINTSOCSEL2.all;
    g_reset_after_soc0ctl = AdcRegs.ADCSOC0CTL.all;
}

static void adc_issue_reset_and_wait(void)
{
    EALLOW;
    AdcRegs.ADCCTL1.bit.RESET = 1U;
    EDIS;

    g_reset_after_adcctl1 = AdcRegs.ADCCTL1.all;
    if (AdcRegs.ADCCTL1.bit.RESET != 0U) {
        test_runtime_fail(ADC_RESET_FAIL_RESET_BIT_STICKY);
    }

    board_delay_us(ADC_RESET_POST_RESET_DELAY_US);
}

static void adc_check_config_reset_defaults(void)
{
    adc_capture_config_after();

    if (g_reset_after_adcctl1 != ADC_RESET_DEFAULT_ADCCTL1) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_adcctl2 != ADC_RESET_DEFAULT_ADCCTL2) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_socprictl != ADC_RESET_DEFAULT_SOCPRICTL) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_samplemode != ADC_RESET_DEFAULT_SAMPLEMODE) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_intsocsel1 != ADC_RESET_DEFAULT_INTSOCSEL1) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_intsocsel2 != ADC_RESET_DEFAULT_INTSOCSEL2) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
    if (g_reset_after_soc0ctl != ADC_RESET_DEFAULT_SOCCTL) {
        test_runtime_fail(ADC_RESET_FAIL_CFG_NOT_DEFAULT);
    }
}

static void adc_test_reset_clears_interrupt_flags(void)
{
    adc_apply_reference_config();
    board_delay_us(ADC_RESET_POWERUP_DELAY_US);
    adc_capture_config_before();

    EALLOW;
    AdcRegs.ADCSOCFRC1.bit.SOC0 = 1U;
    EDIS;

    if (adc_wait_int1() == 0UL) {
        test_runtime_fail(ADC_RESET_FAIL_INT_TIMEOUT);
    }

    g_reset_intflag_before_reset = AdcRegs.ADCINTFLG.all;
    if ((g_reset_intflag_before_reset & 0x0001U) == 0U) {
        test_runtime_fail(ADC_RESET_FAIL_INT_TIMEOUT);
    }

    adc_issue_reset_and_wait();
    adc_check_config_reset_defaults();

    g_reset_intflag_after_reset = AdcRegs.ADCINTFLG.all;
    if (g_reset_intflag_after_reset != 0U) {
        test_runtime_fail(ADC_RESET_FAIL_INTFLAG_NOT_CLEARED);
    }
}

static void adc_test_reset_clears_soc_flags(void)
{
    adc_apply_reference_config();

    EALLOW;
    AdcRegs.ADCSAMPLEMODE.all = 0U;
    AdcRegs.ADCINTSOCSEL1.all = 0U;
    AdcRegs.ADCINTSOCSEL2.all = 0U;
    AdcRegs.ADCSOC0CTL.all = 0U;
    AdcRegs.ADCSOC0CTL.bit.CHSEL = ADC_RESET_SOC0_CHSEL;
    AdcRegs.ADCSOC0CTL.bit.ACQPS = ADC_RESET_LONG_ACQPS;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = 0U;
    AdcRegs.ADCSOC1CTL.all = 0U;
    AdcRegs.ADCSOC1CTL.bit.CHSEL = ADC_RESET_SOC1_CHSEL;
    AdcRegs.ADCSOC1CTL.bit.ACQPS = ADC_RESET_LONG_ACQPS;
    AdcRegs.ADCSOC1CTL.bit.TRIGSEL = 0U;
    AdcRegs.ADCINTFLGCLR.all = 0x01FFU;
    AdcRegs.ADCINTOVFCLR.all = 0x01FFU;
    AdcRegs.ADCSOCOVFCLR1.all = 0xFFFFU;
    EDIS;

    adc_capture_config_before();

    EALLOW;
    AdcRegs.ADCSOCFRC1.bit.SOC1 = 1U;
    EDIS;

    board_delay_us(1UL);

    EALLOW;
    AdcRegs.ADCSOCFRC1.bit.SOC0 = 1U;
    AdcRegs.ADCSOCFRC1.bit.SOC0 = 1U;
    EDIS;

    g_reset_socflg_before_reset = AdcRegs.ADCSOCFLG1.all;
    g_reset_socovf_before_reset = AdcRegs.ADCSOCOVF1.all;

    adc_issue_reset_and_wait();
    adc_check_config_reset_defaults();

    g_reset_socflg_after_reset = AdcRegs.ADCSOCFLG1.all;
    g_reset_socovf_after_reset = AdcRegs.ADCSOCOVF1.all;

    if (g_reset_socflg_after_reset != 0U) {
        test_runtime_fail(ADC_RESET_FAIL_SOCFLAG_NOT_CLEARED);
    }
    if (g_reset_socovf_after_reset != 0U) {
        test_runtime_fail(ADC_RESET_FAIL_SOCOVF_NOT_CLEARED);
    }
}

void main(void)
{
    board_demo_init();
    adc_init_case();
    adc_test_reset_clears_interrupt_flags();
    adc_test_reset_clears_soc_flags();
    test_runtime_pass();
}
