#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for adc_single_soc_basic
#endif

#define ADC_SOC0_CHANNEL_B5          13U
#define ADC_SOC_TRIGGER_SOFTWARE     0U

static void adc_single_soc_basic_init(void)
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

    board_delay_us(ADC_SINGLE_SOC_BASIC_POWERUP_DELAY_US);

    EALLOW;
    AdcRegs.ADCCTL1.bit.VREFLOCONV = 1;

    AdcRegs.INTSEL1N2.bit.INT1SEL = 0;
    AdcRegs.INTSEL1N2.bit.INT1E = 1;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0;

    AdcRegs.ADCSOC0CTL.bit.CHSEL = ADC_SOC0_CHANNEL_B5;
    AdcRegs.ADCSOC0CTL.bit.ACQPS = ADC_SINGLE_SOC_BASIC_ACQPS;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_SOC_TRIGGER_SOFTWARE;
    EDIS;
}

static unsigned int adc_single_soc_basic_check(void)
{
    if (SysCtrlRegs.PCLKCR0.bit.ADCENCLK != 1U) {
        return ADC_SINGLE_SOC_BASIC_FAIL_CLK_EN;
    }

    if (AdcRegs.ADCCTL2.bit.CLKDIV2EN != 1U) {
        return ADC_SINGLE_SOC_BASIC_FAIL_CTL2;
    }

    if ((AdcRegs.ADCCTL1.bit.INTPULSEPOS != 1U) ||
        (AdcRegs.ADCCTL1.bit.ADCREFSEL != 0U) ||
        (AdcRegs.ADCCTL1.bit.ADCREFPWD != 1U) ||
        (AdcRegs.ADCCTL1.bit.ADCBGPWD != 1U) ||
        (AdcRegs.ADCCTL1.bit.ADCPWDN != 1U) ||
        (AdcRegs.ADCCTL1.bit.ADCENABLE != 1U) ||
        (AdcRegs.ADCCTL1.bit.VREFLOCONV != 1U)) {
        return ADC_SINGLE_SOC_BASIC_FAIL_CTL1;
    }

    if ((AdcRegs.INTSEL1N2.bit.INT1SEL != 0U) ||
        (AdcRegs.INTSEL1N2.bit.INT1E != 1U) ||
        (AdcRegs.INTSEL1N2.bit.INT1CONT != 0U)) {
        return ADC_SINGLE_SOC_BASIC_FAIL_INTSEL;
    }

    if ((AdcRegs.ADCSOC0CTL.bit.CHSEL != ADC_SOC0_CHANNEL_B5) ||
        (AdcRegs.ADCSOC0CTL.bit.ACQPS != ADC_SINGLE_SOC_BASIC_ACQPS) ||
        (AdcRegs.ADCSOC0CTL.bit.TRIGSEL != ADC_SOC_TRIGGER_SOFTWARE)) {
        return ADC_SINGLE_SOC_BASIC_FAIL_SOC0;
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;

    if (ADC_SINGLE_SOC_BASIC_ACQPS < 6U) {
        test_runtime_fail(ADC_SINGLE_SOC_BASIC_FAIL_BAD_CONFIG);
    }

    board_demo_init();
    adc_single_soc_basic_init();
    fail_code = adc_single_soc_basic_check();
    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    board_demo_toggle();
    test_runtime_pass();
}
