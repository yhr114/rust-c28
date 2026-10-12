#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "adc_reg_rw_smoke only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_adcctl1_readback_0;
volatile Uint16 g_adcctl1_readback_1;
volatile Uint16 g_adcctl2_readback_5555;
volatile Uint16 g_adcctl2_readback_aaaa;
volatile Uint16 g_intsel_readback[5][2];
volatile Uint16 g_socprictl_readback_5555;
volatile Uint16 g_socprictl_readback_aaaa;
volatile Uint16 g_samplemode_readback_5555;
volatile Uint16 g_samplemode_readback_aaaa;
volatile Uint16 g_intsocsel_readback_5555[2];
volatile Uint16 g_intsocsel_readback_aaaa[2];
volatile Uint16 g_socctl_readback[16];
volatile Uint16 g_reftrim_readback_5555;
volatile Uint16 g_reftrim_readback_aaaa;
volatile Uint16 g_offtrim_readback_5555;
volatile Uint16 g_offtrim_readback_aaaa;
volatile Uint16 g_comphyst_readback_5555;
volatile Uint16 g_comphyst_readback_aaaa;
volatile Uint16 g_status_readback[4];
volatile Uint16 g_clear_readback[3];
volatile Uint16 g_reset_adcctl_readback[2];
volatile Uint16 g_reset_intsel_readback[5];
volatile Uint16 g_reset_socprictl_readback;
volatile Uint16 g_reset_samplemode_readback;
volatile Uint16 g_reset_intsocsel_readback[2];
volatile Uint16 g_reset_socctl_readback[16];
volatile Uint16 g_reset_trim_readback[3];

static void fail_if_ne(Uint16 observed, Uint16 expected, Uint16 fail_code)
{
    if (observed != expected) {
        test_runtime_fail(fail_code);
    }
}

static void adc_init_case(void)
{
    InitAdc();
    AdcOffsetSelfCal();
    board_delay_us(ADC_REG_RW_POWERUP_DELAY_US);
}

static void adc_quiet_registers(void)
{
    EALLOW;
    AdcRegs.INTSEL1N2.all = 0U;
    AdcRegs.INTSEL3N4.all = 0U;
    AdcRegs.INTSEL5N6.all = 0U;
    AdcRegs.INTSEL7N8.all = 0U;
    AdcRegs.INTSEL9N10.all = 0U;
    AdcRegs.ADCINTSOCSEL1.all = 0U;
    AdcRegs.ADCINTSOCSEL2.all = 0U;
    AdcRegs.ADCSAMPLEMODE.all = 0U;
    AdcRegs.SOCPRICTL.all = 0U;
    AdcRegs.ADCINTFLGCLR.all = ADC_REG_RW_INT_MASK;
    AdcRegs.ADCINTOVFCLR.all = ADC_REG_RW_INT_MASK;
    AdcRegs.ADCSOCOVFCLR1.all = 0xFFFFU;
    EDIS;
}

static void adc_check_adcctl1(void)
{
    Uint16 observed;
    Uint16 expected;

    EALLOW;
    AdcRegs.ADCCTL1.all = ADC_REG_RW_ADCCTL1_PATTERN_0;
    EDIS;
    g_adcctl1_readback_0 = AdcRegs.ADCCTL1.all;
    observed = g_adcctl1_readback_0 & ADC_REG_RW_ADCCTL1_CHECK_MASK;
    expected = (ADC_REG_RW_ADCCTL1_PATTERN_0 & ADC_REG_RW_ADCCTL1_RW_MASK) |
               ADC_REG_RW_ADCCTL1_ADCENABLE_RO;
    fail_if_ne(observed, expected, ADC_REG_RW_FAIL_ADCCTL1_PATTERN0);

    EALLOW;
    AdcRegs.ADCCTL1.all = ADC_REG_RW_ADCCTL1_PATTERN_1;
    EDIS;
    g_adcctl1_readback_1 = AdcRegs.ADCCTL1.all;
    observed = g_adcctl1_readback_1 & ADC_REG_RW_ADCCTL1_CHECK_MASK;
    expected = (ADC_REG_RW_ADCCTL1_PATTERN_1 & ADC_REG_RW_ADCCTL1_RW_MASK) |
               ADC_REG_RW_ADCCTL1_ADCENABLE_RO;
    fail_if_ne(observed, expected, ADC_REG_RW_FAIL_ADCCTL1_PATTERN1);

}

static void adc_check_adcctl2(void)
{
    EALLOW;
    AdcRegs.ADCCTL2.all = ADC_REG_RW_WRITE_5555_16;
    EDIS;
    g_adcctl2_readback_5555 = AdcRegs.ADCCTL2.all;
    fail_if_ne(g_adcctl2_readback_5555,
               ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_ADCCTL2,
               ADC_REG_RW_FAIL_ADCCTL2_5555);

    EALLOW;
    AdcRegs.ADCCTL2.all = ADC_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_adcctl2_readback_aaaa = AdcRegs.ADCCTL2.all;
    fail_if_ne(g_adcctl2_readback_aaaa,
               ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_ADCCTL2,
               ADC_REG_RW_FAIL_ADCCTL2_AAAA);
}

static void adc_check_intsel_regs(void)
{
    EALLOW;
    AdcRegs.INTSEL1N2.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.INTSEL3N4.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.INTSEL5N6.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.INTSEL7N8.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.INTSEL9N10.all = ADC_REG_RW_WRITE_5555_16;
    EDIS;

    g_intsel_readback[0][0] = AdcRegs.INTSEL1N2.all;
    g_intsel_readback[1][0] = AdcRegs.INTSEL3N4.all;
    g_intsel_readback[2][0] = AdcRegs.INTSEL5N6.all;
    g_intsel_readback[3][0] = AdcRegs.INTSEL7N8.all;
    g_intsel_readback[4][0] = AdcRegs.INTSEL9N10.all;
    fail_if_ne(g_intsel_readback[0][0], ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL1N2_5555);
    fail_if_ne(g_intsel_readback[1][0], ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL3N4_5555);
    fail_if_ne(g_intsel_readback[2][0], ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL5N6_5555);
    fail_if_ne(g_intsel_readback[3][0], ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL7N8_5555);
    fail_if_ne(g_intsel_readback[4][0], ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_INTSEL9N10,
               ADC_REG_RW_FAIL_INTSEL9N10_5555);

    EALLOW;
    AdcRegs.INTSEL1N2.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.INTSEL3N4.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.INTSEL5N6.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.INTSEL7N8.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.INTSEL9N10.all = ADC_REG_RW_WRITE_AAAA_16;
    EDIS;

    g_intsel_readback[0][1] = AdcRegs.INTSEL1N2.all;
    g_intsel_readback[1][1] = AdcRegs.INTSEL3N4.all;
    g_intsel_readback[2][1] = AdcRegs.INTSEL5N6.all;
    g_intsel_readback[3][1] = AdcRegs.INTSEL7N8.all;
    g_intsel_readback[4][1] = AdcRegs.INTSEL9N10.all;
    fail_if_ne(g_intsel_readback[0][1], ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL1N2_AAAA);
    fail_if_ne(g_intsel_readback[1][1], ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL3N4_AAAA);
    fail_if_ne(g_intsel_readback[2][1], ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL5N6_AAAA);
    fail_if_ne(g_intsel_readback[3][1], ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_INTSEL_PAIR,
               ADC_REG_RW_FAIL_INTSEL7N8_AAAA);
    fail_if_ne(g_intsel_readback[4][1], ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_INTSEL9N10,
               ADC_REG_RW_FAIL_INTSEL9N10_AAAA);
}

static void adc_check_socprictl(void)
{
    EALLOW;
    AdcRegs.SOCPRICTL.all = ADC_REG_RW_WRITE_5555_16;
    EDIS;
    g_socprictl_readback_5555 = AdcRegs.SOCPRICTL.all;
    fail_if_ne(g_socprictl_readback_5555,
               (ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_SOCPRICTL_RW) |
               ADC_REG_RW_SOCPRICTL_RRPOINTER_RESET,
               ADC_REG_RW_FAIL_SOCPRICTL_5555);

    EALLOW;
    AdcRegs.SOCPRICTL.all = ADC_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_socprictl_readback_aaaa = AdcRegs.SOCPRICTL.all;
    fail_if_ne(g_socprictl_readback_aaaa,
               (ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_SOCPRICTL_RW) |
               ADC_REG_RW_SOCPRICTL_RRPOINTER_RESET,
               ADC_REG_RW_FAIL_SOCPRICTL_AAAA);
}

static void adc_check_samplemode_and_feedback(void)
{
    EALLOW;
    AdcRegs.ADCSAMPLEMODE.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.ADCINTSOCSEL1.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.ADCINTSOCSEL2.all = ADC_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_samplemode_readback_5555 = AdcRegs.ADCSAMPLEMODE.all;
    g_intsocsel_readback_5555[0] = AdcRegs.ADCINTSOCSEL1.all;
    g_intsocsel_readback_5555[1] = AdcRegs.ADCINTSOCSEL2.all;
    fail_if_ne(g_samplemode_readback_5555,
               ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_SAMPLEMODE,
               ADC_REG_RW_FAIL_SAMPLEMODE_5555);
    fail_if_ne(g_intsocsel_readback_5555[0], ADC_REG_RW_WRITE_5555_16,
               ADC_REG_RW_FAIL_INTSOCSEL1_5555);
    fail_if_ne(g_intsocsel_readback_5555[1], ADC_REG_RW_WRITE_AAAA_16,
               ADC_REG_RW_FAIL_INTSOCSEL2_5555);

    EALLOW;
    AdcRegs.ADCSAMPLEMODE.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.ADCINTSOCSEL1.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.ADCINTSOCSEL2.all = ADC_REG_RW_WRITE_5555_16;
    EDIS;
    g_samplemode_readback_aaaa = AdcRegs.ADCSAMPLEMODE.all;
    g_intsocsel_readback_aaaa[0] = AdcRegs.ADCINTSOCSEL1.all;
    g_intsocsel_readback_aaaa[1] = AdcRegs.ADCINTSOCSEL2.all;
    fail_if_ne(g_samplemode_readback_aaaa,
               ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_SAMPLEMODE,
               ADC_REG_RW_FAIL_SAMPLEMODE_AAAA);
    fail_if_ne(g_intsocsel_readback_aaaa[0], ADC_REG_RW_WRITE_AAAA_16,
               ADC_REG_RW_FAIL_INTSOCSEL1_AAAA);
    fail_if_ne(g_intsocsel_readback_aaaa[1], ADC_REG_RW_WRITE_5555_16,
               ADC_REG_RW_FAIL_INTSOCSEL2_AAAA);
}

static Uint16 adc_socctl_value(Uint16 soc)
{
    Uint16 trigsel = soc % 19U;
    Uint16 chsel = soc & 0x000FU;
    Uint16 acqps = 6U + (soc % 10U);
    return (Uint16)((trigsel << 11) | (chsel << 6) | acqps);
}

static void adc_check_all_socctl(void)
{
    volatile union ADCSOCxCTL_REG *socctl = &AdcRegs.ADCSOC0CTL;
    Uint16 i;
    Uint16 expected;

    EALLOW;
    for (i = 0U; i < 16U; i++) {
        socctl[i].all = (Uint16)(adc_socctl_value(i) | ADC_REG_RW_SOCCTL_RSVD_BIT);
    }
    EDIS;

    for (i = 0U; i < 16U; i++) {
        g_socctl_readback[i] = socctl[i].all;
        expected = adc_socctl_value(i) & ADC_REG_RW_MASK_SOCCTL;
        fail_if_ne(g_socctl_readback[i], expected,
                   (Uint16)(ADC_REG_RW_FAIL_SOCCTL_BASE + i));
    }

}

static void adc_check_trim_regs(void)
{
    EALLOW;
    AdcRegs.ADCREFTRIM.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.ADCOFFTRIM.all = ADC_REG_RW_WRITE_5555_16;
    AdcRegs.COMPHYSTCTL.all = ADC_REG_RW_WRITE_5555_16;
    EDIS;
    g_reftrim_readback_5555 = AdcRegs.ADCREFTRIM.all;
    g_offtrim_readback_5555 = AdcRegs.ADCOFFTRIM.all;
    g_comphyst_readback_5555 = AdcRegs.COMPHYSTCTL.all;
    fail_if_ne(g_reftrim_readback_5555, ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_REFTRIM,
               ADC_REG_RW_FAIL_REFTRIM_5555);
    fail_if_ne(g_offtrim_readback_5555, ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_OFFTRIM,
               ADC_REG_RW_FAIL_OFFTRIM_5555);
    fail_if_ne(g_comphyst_readback_5555, ADC_REG_RW_WRITE_5555_16 & ADC_REG_RW_MASK_COMPHYST,
               ADC_REG_RW_FAIL_COMPHYST_5555);

    EALLOW;
    AdcRegs.ADCREFTRIM.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.ADCOFFTRIM.all = ADC_REG_RW_WRITE_AAAA_16;
    AdcRegs.COMPHYSTCTL.all = ADC_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_reftrim_readback_aaaa = AdcRegs.ADCREFTRIM.all;
    g_offtrim_readback_aaaa = AdcRegs.ADCOFFTRIM.all;
    g_comphyst_readback_aaaa = AdcRegs.COMPHYSTCTL.all;
    fail_if_ne(g_reftrim_readback_aaaa, ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_REFTRIM,
               ADC_REG_RW_FAIL_REFTRIM_AAAA);
    fail_if_ne(g_offtrim_readback_aaaa, ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_OFFTRIM,
               ADC_REG_RW_FAIL_OFFTRIM_AAAA);
    fail_if_ne(g_comphyst_readback_aaaa, ADC_REG_RW_WRITE_AAAA_16 & ADC_REG_RW_MASK_COMPHYST,
               ADC_REG_RW_FAIL_COMPHYST_AAAA);
}

static void adc_check_status_write_ignored(void)
{
    EALLOW;
    AdcRegs.ADCINTFLGCLR.all = ADC_REG_RW_INT_MASK;
    AdcRegs.ADCINTOVFCLR.all = ADC_REG_RW_INT_MASK;
    AdcRegs.ADCSOCOVFCLR1.all = 0xFFFFU;
    AdcRegs.ADCINTFLG.all = 0xFFFFU;
    AdcRegs.ADCINTOVF.all = 0xFFFFU;
    AdcRegs.ADCSOCFLG1.all = 0xFFFFU;
    AdcRegs.ADCSOCOVF1.all = 0xFFFFU;
    EDIS;

    g_status_readback[0] = AdcRegs.ADCINTFLG.all;
    g_status_readback[1] = AdcRegs.ADCINTOVF.all;
    g_status_readback[2] = AdcRegs.ADCSOCFLG1.all;
    g_status_readback[3] = AdcRegs.ADCSOCOVF1.all;

    fail_if_ne((Uint16)(g_status_readback[0] & ADC_REG_RW_INT_MASK), 0U,
               ADC_REG_RW_FAIL_ADCINTFLG_RO);
    fail_if_ne((Uint16)(g_status_readback[1] & ADC_REG_RW_INT_MASK), 0U,
               ADC_REG_RW_FAIL_ADCINTOVF_RO);
    fail_if_ne(g_status_readback[2], 0U, ADC_REG_RW_FAIL_ADCSOCFLG_RO);
    fail_if_ne(g_status_readback[3], 0U, ADC_REG_RW_FAIL_ADCSOCOVF_RO);
}

static void adc_check_clear_regs_read_zero(void)
{
    EALLOW;
    AdcRegs.ADCINTFLGCLR.all = 0xFFFFU;
    AdcRegs.ADCINTOVFCLR.all = 0xFFFFU;
    AdcRegs.ADCSOCOVFCLR1.all = 0xFFFFU;
    EDIS;

    g_clear_readback[0] = AdcRegs.ADCINTFLGCLR.all;
    g_clear_readback[1] = AdcRegs.ADCINTOVFCLR.all;
    g_clear_readback[2] = AdcRegs.ADCSOCOVFCLR1.all;
    fail_if_ne(g_clear_readback[0], 0U, ADC_REG_RW_FAIL_ADCINTFLGCLR_R0);
    fail_if_ne(g_clear_readback[1], 0U, ADC_REG_RW_FAIL_ADCINTOVFCLR_R0);
    fail_if_ne(g_clear_readback[2], 0U, ADC_REG_RW_FAIL_ADCSOCOVFCLR_R0);
}

static void adc_check_soft_reset_defaults(void)
{
    volatile union ADCSOCxCTL_REG *socctl = &AdcRegs.ADCSOC0CTL;
    Uint16 i;

    EALLOW;
    AdcRegs.ADCCTL1.bit.RESET = 1U;
    EDIS;

    if (AdcRegs.ADCCTL1.bit.RESET != 0U) {
        test_runtime_fail(ADC_REG_RW_FAIL_RESET_BIT_STICKY);
    }
    board_delay_us(ADC_REG_RW_POST_RESET_DELAY_US);

    g_reset_adcctl_readback[0] = AdcRegs.ADCCTL1.all;
    g_reset_adcctl_readback[1] = AdcRegs.ADCCTL2.all;
    g_reset_intsel_readback[0] = AdcRegs.INTSEL1N2.all;
    g_reset_intsel_readback[1] = AdcRegs.INTSEL3N4.all;
    g_reset_intsel_readback[2] = AdcRegs.INTSEL5N6.all;
    g_reset_intsel_readback[3] = AdcRegs.INTSEL7N8.all;
    g_reset_intsel_readback[4] = AdcRegs.INTSEL9N10.all;
    g_reset_socprictl_readback = AdcRegs.SOCPRICTL.all;
    g_reset_samplemode_readback = AdcRegs.ADCSAMPLEMODE.all;
    g_reset_intsocsel_readback[0] = AdcRegs.ADCINTSOCSEL1.all;
    g_reset_intsocsel_readback[1] = AdcRegs.ADCINTSOCSEL2.all;
    g_reset_trim_readback[0] = AdcRegs.ADCREFTRIM.all;
    g_reset_trim_readback[1] = AdcRegs.ADCOFFTRIM.all;
    g_reset_trim_readback[2] = AdcRegs.COMPHYSTCTL.all;

    fail_if_ne(g_reset_adcctl_readback[0], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_ADCCTL1);
    fail_if_ne(g_reset_adcctl_readback[1], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_ADCCTL2);
    for (i = 0U; i < 5U; i++) {
        fail_if_ne(g_reset_intsel_readback[i], ADC_REG_RW_RESET_DEFAULT,
                   (Uint16)(ADC_REG_RW_FAIL_RESET_INTSEL_BASE + i));
    }
    fail_if_ne(g_reset_socprictl_readback,
               ADC_REG_RW_RESET_SOCPRICTL_DEFAULT,
               ADC_REG_RW_FAIL_RESET_SOCPRICTL);
    fail_if_ne(g_reset_samplemode_readback, ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_SAMPLEMODE);
    fail_if_ne(g_reset_intsocsel_readback[0], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_INTSOCSEL1);
    fail_if_ne(g_reset_intsocsel_readback[1], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_INTSOCSEL2);

    for (i = 0U; i < 16U; i++) {
        g_reset_socctl_readback[i] = socctl[i].all;
        fail_if_ne(g_reset_socctl_readback[i], ADC_REG_RW_RESET_DEFAULT,
                   (Uint16)(ADC_REG_RW_FAIL_RESET_SOCCTL_BASE + i));
    }

    fail_if_ne(g_reset_trim_readback[0], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_REFTRIM);
    fail_if_ne(g_reset_trim_readback[1], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_OFFTRIM);
    fail_if_ne(g_reset_trim_readback[2], ADC_REG_RW_RESET_DEFAULT,
               ADC_REG_RW_FAIL_RESET_COMPHYST);
}

void main(void)
{
    board_demo_init();
    adc_init_case();
    adc_quiet_registers();
    adc_check_adcctl1();
    adc_check_adcctl2();
    adc_check_intsel_regs();
    adc_check_socprictl();
    adc_check_samplemode_and_feedback();
    adc_check_all_socctl();
    adc_check_trim_regs();
    adc_check_status_write_ignored();
    adc_check_clear_regs_read_zero();
    adc_check_soft_reset_defaults();
    test_runtime_pass();
}
