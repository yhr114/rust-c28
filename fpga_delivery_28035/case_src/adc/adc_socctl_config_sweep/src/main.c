#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "adc_socctl_config_sweep only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_socctl_readback[16];
volatile Uint16 g_socctl_result[16];

static void check_socctl_pattern(Uint16 pattern, Uint16 fail_base)
{
    volatile union ADCSOCxCTL_REG *socctl = &AdcRegs.ADCSOC0CTL;
    Uint16 i;

    EALLOW;
    for (i = 0U; i < 16U; i++) {
        socctl[i].all = pattern;
    }
    EDIS;

    for (i = 0U; i < 16U; i++) {
        g_socctl_readback[i] = socctl[i].all;
        if (g_socctl_readback[i] != pattern) {
            test_runtime_fail((Uint16)(fail_base + i));
        }
    }
}

static void check_socctl_reset(void)
{
    volatile union ADCSOCxCTL_REG *socctl = &AdcRegs.ADCSOC0CTL;
    Uint16 i;

    EALLOW;
    AdcRegs.ADCCTL1.bit.RESET = 1U;
    EDIS;
    asm(" NOP");
    asm(" NOP");

    for (i = 0U; i < 16U; i++) {
        g_socctl_readback[i] = socctl[i].all;
        if (g_socctl_readback[i] != 0U) {
            test_runtime_fail((Uint16)(ADC_SOCCTL_FAIL_RESET_BASE + i));
        }
    }
}

static void enable_adc_conversion(void)
{
    EALLOW;
    AdcRegs.ADCCTL2.bit.CLKDIV2EN = 0U;
    AdcRegs.ADCCTL1.bit.INTPULSEPOS = 1U;
    AdcRegs.ADCCTL1.bit.ADCREFPWD = 1U;
    AdcRegs.ADCCTL1.bit.ADCBGPWD = 1U;
    AdcRegs.ADCCTL1.bit.ADCPWDN = 1U;
    AdcRegs.ADCCTL1.bit.ADCENABLE = 1U;
    AdcRegs.INTSEL1N2.bit.INT1E = 1U;
    AdcRegs.INTSEL1N2.bit.INT1CONT = 0U;
    EDIS;

    board_delay_us(ADC_SOCCTL_POWERUP_DELAY_US);
}

static void convert_each_soc(Uint16 eoc_fail_base, Uint16 busy_fail_base)
{
    volatile Uint16 *result = &AdcResult.ADCRESULT0;
    Uint32 timeout;
    Uint16 i;
    Uint16 mask;

    for (i = 0U; i < 16U; i++) {
        mask = (Uint16)(1U << i);

        EALLOW;
        AdcRegs.INTSEL1N2.bit.INT1SEL = i;
        EDIS;
        AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1U;
        AdcRegs.ADCSOCFRC1.all = mask;

        timeout = 0UL;
        while ((AdcRegs.ADCINTFLG.all & 0x0001U) == 0U) {
            if (++timeout >= ADC_SOCCTL_POLL_TIMEOUT) {
                test_runtime_fail((Uint16)(eoc_fail_base + i));
            }
        }

        g_socctl_result[i] = result[i];
        if ((AdcRegs.ADCSOCFLG1.all & mask) != 0U) {
            test_runtime_fail((Uint16)(busy_fail_base + i));
        }
        AdcRegs.ADCINTFLGCLR.bit.ADCINT1 = 1U;
    }
}

void main(void)
{
    board_demo_init();
    EALLOW;
    SysCtrlRegs.PCLKCR0.bit.ADCENCLK = 1U;
    AdcRegs.ADCCTL1.bit.RESET = 1U;
    EDIS;
    asm(" NOP");
    asm(" NOP");

    /* Isolate the sweep from ADCINT feedback; software force drives each SOC. */
    EALLOW;
    AdcRegs.ADCINTSOCSEL1.all = 0U;
    AdcRegs.ADCINTSOCSEL2.all = 0U;
    EDIS;
    enable_adc_conversion();

    check_socctl_pattern(ADC_SOCCTL_PATTERN_ALL_HIGH,
                         ADC_SOCCTL_FAIL_HIGH_BASE);
    convert_each_soc(ADC_SOCCTL_FAIL_HIGH_EOC_BASE,
                     ADC_SOCCTL_FAIL_HIGH_BUSY_BASE);
    check_socctl_pattern(ADC_SOCCTL_PATTERN_TRIG18_LOW,
                         ADC_SOCCTL_FAIL_TRIG18_BASE);
    convert_each_soc(ADC_SOCCTL_FAIL_LOW_EOC_BASE,
                     ADC_SOCCTL_FAIL_LOW_BUSY_BASE);
    check_socctl_reset();

    board_demo_toggle();
    test_runtime_pass();
}
