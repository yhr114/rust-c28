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

#define ADC_INT_SW_TRIGSEL      0U
#define ADC_INT_EOC_SEL_SOC0    0U
#define ADC_INT_MASK_ALL        0x01FFU

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

static void adc_clear_interrupt_status(void)
{
    EALLOW;
    AdcRegs.ADCINTFLGCLR.all = ADC_INT_MASK_ALL;
    AdcRegs.ADCINTOVFCLR.all = ADC_INT_MASK_ALL;
    EDIS;
    board_delay_us(1UL);
}

static void adc_config_soc0(void)
{
    EALLOW;
    AdcRegs.ADCSOC0CTL.bit.CHSEL   = 0U;
    AdcRegs.ADCSOC0CTL.bit.ACQPS   = 6U;
    AdcRegs.ADCSOC0CTL.bit.TRIGSEL = ADC_INT_SW_TRIGSEL;
    EDIS;
}

static void adc_config_continuous_interrupt(unsigned int int_idx)
{
    unsigned int reg_idx;
    Uint16 value;

    reg_idx = int_idx >> 1;
    value = (Uint16)((ADC_INT_EOC_SEL_SOC0 & 0x001FU) | 0x0020U | 0x0040U);
    if ((int_idx & 1U) != 0U) {
        value = (Uint16)(value << 8);
    }

    EALLOW;
    AdcRegs.INTSEL1N2.all = 0U;
    AdcRegs.INTSEL3N4.all = 0U;
    AdcRegs.INTSEL5N6.all = 0U;
    AdcRegs.INTSEL7N8.all = 0U;
    AdcRegs.INTSEL9N10.all = 0U;

    switch (reg_idx) {
    case 0U:
        AdcRegs.INTSEL1N2.all = value;
        break;
    case 1U:
        AdcRegs.INTSEL3N4.all = value;
        break;
    case 2U:
        AdcRegs.INTSEL5N6.all = value;
        break;
    case 3U:
        AdcRegs.INTSEL7N8.all = value;
        break;
    default:
        AdcRegs.INTSEL9N10.all = value;
        break;
    }
    EDIS;
}

static unsigned int wait_mask_set(volatile Uint16 *reg, Uint16 mask)
{
    unsigned int t = 0U;

    while (((*reg) & mask) == 0U) {
        if (++t >= ADC_INTCONT_POLL) {
            return 0U;
        }
    }
    return 1U;
}

static void adc_force_soc0(void)
{
    AdcRegs.ADCSOCFRC1.all = 0x0001U;
}

static void adc_run_int_cont_sweep(unsigned int int_idx)
{
    volatile unsigned int r;
    Uint16 mask;

    mask = (Uint16)(1U << int_idx);

    adc_clear_interrupt_status();
    adc_config_continuous_interrupt(int_idx);

    /* First trigger: selected ADCINTx should set its flag and pulse ADCINT2PIE[x]. */
    adc_force_soc0();
    if (!wait_mask_set(&AdcRegs.ADCINTFLG.all, mask)) {
        test_runtime_fail((Uint16)(ADC_INTCONT_FAIL_FIRST_BASE + int_idx));
    }
    r = AdcResult.ADCRESULT0; (void)r;

    if ((AdcRegs.ADCINTFLG.all & mask) == 0U) {
        test_runtime_fail((Uint16)(ADC_INTCONT_FAIL_AUTO_CLR_BASE + int_idx));
    }

    /* INTCONT=1 keeps the PIE pulse path active even while ADCINTFLG is held. */
    /* Recovery is checked by flag reassertion; OVF can pulse too briefly for C. */
    adc_force_soc0();
    if (!wait_mask_set(&AdcRegs.ADCINTOVF.all, mask)) {
        test_runtime_fail((Uint16)(ADC_INTCONT_FAIL_OVF_BASE + int_idx));
    }
    r = AdcResult.ADCRESULT0; (void)r;
    if ((AdcRegs.ADCINTFLG.all & mask) == 0U) {
        test_runtime_fail((Uint16)(ADC_INTCONT_FAIL_FLAG_GONE_BASE + int_idx));
    }

    EALLOW;
    AdcRegs.ADCINTFLGCLR.all = mask;
    AdcRegs.ADCINTOVFCLR.all = mask;
    EDIS;
    board_delay_us(1UL);

    adc_force_soc0();
    if (!wait_mask_set(&AdcRegs.ADCINTFLG.all, mask)) {
        test_runtime_fail((Uint16)(ADC_INTCONT_FAIL_RECOV_BASE + int_idx));
    }
    r = AdcResult.ADCRESULT0; (void)r;

    EALLOW;
    AdcRegs.ADCINTFLGCLR.all = mask;
    AdcRegs.ADCINTOVFCLR.all = mask;
    EDIS;
    board_delay_us(1UL);
}

void main(void)
{
    unsigned int int_idx;

    board_demo_init();
    adc_base_init();
    adc_config_soc0();

    for (int_idx = 0U; int_idx < 9U; int_idx++) {
        adc_run_int_cont_sweep(int_idx);
    }

    board_demo_toggle();
    test_runtime_pass();
}
