#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_interrupt_integration only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_disabled_ecflg[7];
volatile Uint16 g_enabled_ecflg[7];
volatile Uint16 g_cleared_ecflg[7];
volatile Uint16 g_source_under_test[7];
volatile Uint16 g_ecap_isr_count;
volatile Uint16 g_ecap_isr_expected_source;
volatile Uint16 g_ecap_isr_slot;
volatile Uint16 g_ecap_isr_flags[ECAP_INT_ISR_SAMPLE_COUNT];
volatile Uint16 g_ecap_isr_source_match[ECAP_INT_ISR_SAMPLE_COUNT];
volatile Uint32 g_ecap_isr_natural_ovf_tsctr;

__interrupt void ecap1_route_isr(void)
{
    Uint16 flags = ECap1Regs.ECFLG.all;
    Uint16 slot = g_ecap_isr_slot;

    if (slot < ECAP_INT_ISR_SAMPLE_COUNT) {
        g_ecap_isr_flags[slot] = flags;
        if ((flags & (g_ecap_isr_expected_source | ECAP_INT_GLOBAL)) ==
            (g_ecap_isr_expected_source | ECAP_INT_GLOBAL)) {
            g_ecap_isr_source_match[slot]++;
        }
    }

    g_ecap_isr_count++;
    ECap1Regs.ECCLR.all = (Uint16)((flags & 0x00FEU) | ECAP_INT_GLOBAL);
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP4;
}

static void ecap_int_init_base(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x00FFU;
    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;
}

static void set_cap_mode(void)
{
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
}

static void set_apwm_quiet_mode(void)
{
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.TSCTR = 3UL;
    ECap1Regs.CAP1 = 100UL;
    ECap1Regs.CAP2 = 50UL;
    ECap1Regs.CAP3 = 100UL;
    ECap1Regs.CAP4 = 50UL;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 1U;
}

static void select_mode_for_source(Uint16 source_mask)
{
    if ((source_mask == ECAP_INT_SRC_CTR_PRD) ||
        (source_mask == ECAP_INT_SRC_CTR_CMP)) {
        set_apwm_quiet_mode();
    } else {
        set_cap_mode();
    }
}

static void clear_source_and_int(Uint16 source_mask)
{
    ECap1Regs.ECCLR.all = (source_mask | ECAP_INT_GLOBAL);
}

static Uint16 wait_for_isr_count(Uint16 expected_count)
{
    Uint32 timeout = ECAP_INT_ISR_WAIT_LOOPS;

    while (timeout > 0UL) {
        if (g_ecap_isr_count >= expected_count) {
            return 1U;
        }
        timeout--;
    }

    return 0U;
}

static void install_ecap1_cpu_route(void)
{
    DINT;
    EALLOW;
    PieVectTable.ECAP1_INT = &ecap1_route_isr;
    EDIS;

    PieCtrlRegs.PIEACK.all = PIEACK_GROUP4;
    PieCtrlRegs.PIECTRL.bit.ENPIE = 1U;
    PieCtrlRegs.PIEIER4.bit.INTx1 = 0U;
    IER |= M_INT4;

    if ((PieCtrlRegs.PIECTRL.bit.ENPIE != 1U) ||
        ((IER & M_INT4) == 0U)) {
        test_runtime_fail(ECAP_INT_FAIL_ROUTE_CONFIG);
    }

    EINT;
    ERTM;
}

static void prepare_isr_source(Uint16 source_mask, Uint16 slot)
{
    ECap1Regs.ECEINT.all = 0U;
    clear_source_and_int(0x00FEU);
    select_mode_for_source(source_mask);

    g_ecap_isr_expected_source = source_mask;
    g_ecap_isr_slot = slot;
    g_ecap_isr_flags[slot] = 0U;
    g_ecap_isr_source_match[slot] = 0U;

    ECap1Regs.ECEINT.all = source_mask;
    if ((ECap1Regs.ECEINT.all & source_mask) != source_mask) {
        test_runtime_fail(ECAP_INT_FAIL_ECEINT_READBACK);
    }
}

static void verify_isr_delivery(Uint16 source_mask,
                                Uint16 slot,
                                Uint16 count_before)
{
    if (wait_for_isr_count((Uint16)(count_before + 1U)) == 0U) {
        test_runtime_fail(ECAP_INT_FAIL_ISR_TIMEOUT);
    }

    board_delay_us(ECAP_INT_ISR_QUIET_US);
    if (g_ecap_isr_count != (Uint16)(count_before + 1U)) {
        test_runtime_fail(ECAP_INT_FAIL_ISR_COUNT);
    }
    if ((g_ecap_isr_source_match[slot] != 1U) ||
        ((g_ecap_isr_flags[slot] & (source_mask | ECAP_INT_GLOBAL)) !=
         (source_mask | ECAP_INT_GLOBAL))) {
        test_runtime_fail(ECAP_INT_FAIL_ISR_SNAPSHOT);
    }
    if ((ECap1Regs.ECFLG.all & (source_mask | ECAP_INT_GLOBAL)) != 0U) {
        test_runtime_fail(ECAP_INT_FAIL_ISR_CLEAR);
    }
}

static void check_pie_mask_and_pending_release(void)
{
    prepare_isr_source(ECAP_INT_SRC_CEVT1, 0U);
    PieCtrlRegs.PIEIER4.bit.INTx1 = 0U;
    ECap1Regs.ECFRC.all = ECAP_INT_SRC_CEVT1;
    board_delay_us(ECAP_INT_ISR_QUIET_US);

    if (g_ecap_isr_count != 0U) {
        test_runtime_fail(ECAP_INT_FAIL_PIE_MASK);
    }
    if ((ECap1Regs.ECFLG.all & (ECAP_INT_SRC_CEVT1 | ECAP_INT_GLOBAL)) !=
        (ECAP_INT_SRC_CEVT1 | ECAP_INT_GLOBAL)) {
        test_runtime_fail(ECAP_INT_FAIL_PENDING_FLAGS);
    }

    PieCtrlRegs.PIEIER4.bit.INTx1 = 1U;
    if (PieCtrlRegs.PIEIER4.bit.INTx1 != 1U) {
        test_runtime_fail(ECAP_INT_FAIL_ROUTE_CONFIG);
    }
    verify_isr_delivery(ECAP_INT_SRC_CEVT1, 0U, 0U);
}

static void check_forced_source_isr(Uint16 source_mask, Uint16 slot)
{
    Uint16 count_before = g_ecap_isr_count;

    prepare_isr_source(source_mask, slot);
    ECap1Regs.ECFRC.all = source_mask;
    verify_isr_delivery(source_mask, slot, count_before);
}

static void check_natural_overflow_isr(void)
{
    Uint16 count_before = g_ecap_isr_count;

    prepare_isr_source(ECAP_INT_SRC_CTROVF, 8U);
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.TSCTR = ECAP_INT_OVF_PRELOAD;
    clear_source_and_int(ECAP_INT_SRC_CTROVF);
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;

    verify_isr_delivery(ECAP_INT_SRC_CTROVF, 8U, count_before);
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    g_ecap_isr_natural_ovf_tsctr = ECap1Regs.TSCTR;
    if (g_ecap_isr_natural_ovf_tsctr >= ECAP_INT_OVF_PRELOAD) {
        test_runtime_fail(ECAP_INT_FAIL_NATURAL_OVF);
    }
}

static void check_cpu_interrupt_route(void)
{
    g_ecap_isr_count = 0U;
    install_ecap1_cpu_route();

    check_pie_mask_and_pending_release();
    check_forced_source_isr(ECAP_INT_SRC_CEVT1, 1U);
    check_forced_source_isr(ECAP_INT_SRC_CEVT2, 2U);
    check_forced_source_isr(ECAP_INT_SRC_CEVT3, 3U);
    check_forced_source_isr(ECAP_INT_SRC_CEVT4, 4U);
    check_forced_source_isr(ECAP_INT_SRC_CTROVF, 5U);
    check_forced_source_isr(ECAP_INT_SRC_CTR_PRD, 6U);
    check_forced_source_isr(ECAP_INT_SRC_CTR_CMP, 7U);
    check_natural_overflow_isr();

    DINT;
    PieCtrlRegs.PIEIER4.bit.INTx1 = 0U;
    ECap1Regs.ECEINT.all = 0U;
    clear_source_and_int(0x00FEU);
}

static void check_one_interrupt_source(Uint16 source_mask, Uint16 slot)
{
    Uint16 disabled_flags;
    Uint16 enabled_flags;
    Uint16 cleared_flags;

    g_source_under_test[slot] = source_mask;
    select_mode_for_source(source_mask);

    ECap1Regs.ECEINT.all = 0U;
    clear_source_and_int(source_mask);
    ECap1Regs.ECFRC.all = source_mask;
    disabled_flags = ECap1Regs.ECFLG.all;
    g_disabled_ecflg[slot] = disabled_flags;

    if ((disabled_flags & source_mask) != source_mask) {
        test_runtime_fail(ECAP_INT_FAIL_DISABLED_SOURCE);
    }
    if ((disabled_flags & ECAP_INT_GLOBAL) != 0U) {
        test_runtime_fail(ECAP_INT_FAIL_DISABLED_INT);
    }

    clear_source_and_int(source_mask);
    ECap1Regs.ECEINT.all = source_mask;
    if ((ECap1Regs.ECEINT.all & source_mask) != source_mask) {
        test_runtime_fail(ECAP_INT_FAIL_ECEINT_READBACK);
    }

    ECap1Regs.ECFRC.all = source_mask;
    enabled_flags = ECap1Regs.ECFLG.all;
    g_enabled_ecflg[slot] = enabled_flags;

    if ((enabled_flags & source_mask) != source_mask) {
        test_runtime_fail(ECAP_INT_FAIL_ENABLED_SOURCE);
    }
    if ((enabled_flags & ECAP_INT_GLOBAL) == 0U) {
        test_runtime_fail(ECAP_INT_FAIL_ENABLED_INT);
    }

    clear_source_and_int(source_mask);
    cleared_flags = ECap1Regs.ECFLG.all;
    g_cleared_ecflg[slot] = cleared_flags;

    if ((cleared_flags & source_mask) != 0U) {
        test_runtime_fail(ECAP_INT_FAIL_CLEAR_SOURCE);
    }
    if ((cleared_flags & ECAP_INT_GLOBAL) != 0U) {
        test_runtime_fail(ECAP_INT_FAIL_CLEAR_INT);
    }
}

void main(void)
{
    board_demo_init();
    DINT;
    ecap_int_init_base();

    check_one_interrupt_source(ECAP_INT_SRC_CEVT1, 0U);
    check_one_interrupt_source(ECAP_INT_SRC_CEVT2, 1U);
    check_one_interrupt_source(ECAP_INT_SRC_CEVT3, 2U);
    check_one_interrupt_source(ECAP_INT_SRC_CEVT4, 3U);
    check_one_interrupt_source(ECAP_INT_SRC_CTROVF, 4U);
    check_one_interrupt_source(ECAP_INT_SRC_CTR_PRD, 5U);
    check_one_interrupt_source(ECAP_INT_SRC_CTR_CMP, 6U);

    check_cpu_interrupt_route();

    test_runtime_pass();
}
