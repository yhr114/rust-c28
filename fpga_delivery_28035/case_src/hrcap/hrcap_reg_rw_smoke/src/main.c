/*
 * HRCAP Type-0 basic register smoke for F28035.
 *
 * This case intentionally treats HCICLR/HCIFRC as actions and HCCOUNTER/
 * HCCAPCNT* as hardware-owned state. It does not test HCCAL or delay-chain
 * precision, which require a calibrated timing model.
 */
#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "hrcap_reg_rw_smoke only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_reset_hcctl1;
volatile Uint16 g_reset_hcctl2;
volatile Uint16 g_hcctl1_blocked;
volatile Uint16 g_hcctl2_blocked;
volatile Uint16 g_hcctl1_pattern_a;
volatile Uint16 g_hcctl1_pattern_b;
volatile Uint16 g_hcctl2_pattern_a;
volatile Uint16 g_hcctl2_pattern_b;
volatile Uint16 g_hcifr1_forced;
volatile Uint16 g_hcifr2_forced;
volatile Uint16 g_hcifr1_cleared;
volatile Uint16 g_hcifr2_cleared;
volatile Uint16 g_hciclr1_readback;
volatile Uint16 g_hciclr2_readback;
volatile Uint16 g_hcifrc1_readback;
volatile Uint16 g_hcifrc2_readback;

static void hrcap_enable_clocks(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = 1U;
    SysCtrlRegs.PCLKCR2.bit.HRCAP2ENCLK = 1U;
    EDIS;
}

static Uint16 wait_for_flags(volatile struct HRCAP_REGS *regs, Uint16 mask)
{
    Uint32 timeout;

    for (timeout = 0UL; timeout < HRCAP_REG_RW_POLL_LIMIT; ++timeout) {
        if ((regs->HCIFR.all & mask) == mask) {
            return 1U;
        }
    }
    return 0U;
}

static Uint16 wait_for_flags_clear(volatile struct HRCAP_REGS *regs, Uint16 mask)
{
    Uint32 timeout;

    for (timeout = 0UL; timeout < HRCAP_REG_RW_POLL_LIMIT; ++timeout) {
        if ((regs->HCIFR.all & mask) == 0U) {
            return 1U;
        }
    }
    return 0U;
}

static void clear_all_flags(volatile struct HRCAP_REGS *regs)
{
    EALLOW;
    regs->HCICLR.all = HRCAP_REG_RW_HCIFR_ALL_MASK;
    EDIS;
}

static void check_hcctl(volatile struct HRCAP_REGS *regs,
                        volatile Uint16 *blocked,
                        volatile Uint16 *pattern_a,
                        volatile Uint16 *pattern_b,
                        Uint16 fail_blocked,
                        Uint16 fail_pattern_a,
                        Uint16 fail_pattern_b)
{
    EALLOW;
    regs->HCCTL.all = 0U;
    EDIS;

    /* HCCTL is EALLOW protected; the disabled write must have no effect. */
    regs->HCCTL.all = HRCAP_REG_RW_HCCTL_PATTERN_A;
    *blocked = regs->HCCTL.all;
    if ((*blocked & HRCAP_REG_RW_HCCTL_MASK) != 0U) {
        test_runtime_fail(fail_blocked);
    }

    EALLOW;
    regs->HCCTL.all = HRCAP_REG_RW_HCCTL_PATTERN_A;
    EDIS;
    *pattern_a = regs->HCCTL.all;
    if (*pattern_a !=
        (HRCAP_REG_RW_HCCTL_PATTERN_A & HRCAP_REG_RW_HCCTL_MASK)) {
        test_runtime_fail(fail_pattern_a);
    }

    EALLOW;
    regs->HCCTL.all = HRCAP_REG_RW_HCCTL_PATTERN_B;
    EDIS;
    *pattern_b = regs->HCCTL.all;
    if (*pattern_b !=
        (HRCAP_REG_RW_HCCTL_PATTERN_B & HRCAP_REG_RW_HCCTL_MASK)) {
        test_runtime_fail(fail_pattern_b);
    }
}

static void check_force_clear(volatile struct HRCAP_REGS *regs,
                              volatile Uint16 *forced,
                              volatile Uint16 *cleared,
                              volatile Uint16 *clear_readback,
                              volatile Uint16 *force_readback,
                              Uint16 fail_force,
                              Uint16 fail_global_int,
                              Uint16 fail_clear,
                              Uint16 fail_action_read)
{
    /* Enable the three forceable interrupt sources; SOFTRESET remains zero. */
    EALLOW;
    regs->HCCTL.all = HRCAP_REG_RW_HCIFR_EVENT_MASK;
    regs->HCICLR.all = HRCAP_REG_RW_HCIFR_ALL_MASK;
    EDIS;

    regs->HCIFRC.all = HRCAP_REG_RW_HCIFR_EVENT_MASK;
    if (!wait_for_flags(regs, HRCAP_REG_RW_HCIFR_EVENT_MASK)) {
        test_runtime_fail(fail_force);
    }

    *forced = regs->HCIFR.all;
    if (((*forced & HRCAP_REG_RW_HCIFR_EVENT_MASK) !=
         HRCAP_REG_RW_HCIFR_EVENT_MASK) ||
        ((*forced & 0x0001U) == 0U)) {
        test_runtime_fail(fail_global_int);
    }

    EALLOW;
    regs->HCICLR.all = HRCAP_REG_RW_HCIFR_ALL_MASK;
    EDIS;
    if (!wait_for_flags_clear(regs, HRCAP_REG_RW_HCIFR_ALL_MASK)) {
        test_runtime_fail(fail_clear);
    }

    *cleared = regs->HCIFR.all;
    *clear_readback = regs->HCICLR.all;
    *force_readback = regs->HCIFRC.all;
    if (((*cleared & HRCAP_REG_RW_HCIFR_ALL_MASK) != 0U) ||
        (*clear_readback != 0U) || (*force_readback != 0U)) {
        test_runtime_fail(fail_action_read);
    }
}

void main(void)
{
    board_demo_init();
    hrcap_enable_clocks();

    g_reset_hcctl1 = HRCap1Regs.HCCTL.all;
    g_reset_hcctl2 = HRCap2Regs.HCCTL.all;
    if (g_reset_hcctl1 != 0U) {
        test_runtime_fail(HRCAP_REG_RW_FAIL_RESET_HCCTL1);
    }
    if (g_reset_hcctl2 != 0U) {
        test_runtime_fail(HRCAP_REG_RW_FAIL_RESET_HCCTL2);
    }

    check_hcctl(&HRCap1Regs, &g_hcctl1_blocked,
                &g_hcctl1_pattern_a, &g_hcctl1_pattern_b,
                HRCAP_REG_RW_FAIL_EALLOW_BLOCK1,
                HRCAP_REG_RW_FAIL_RW_HCCTL1_A,
                HRCAP_REG_RW_FAIL_RW_HCCTL1_B);
    check_hcctl(&HRCap2Regs, &g_hcctl2_blocked,
                &g_hcctl2_pattern_a, &g_hcctl2_pattern_b,
                HRCAP_REG_RW_FAIL_EALLOW_BLOCK2,
                HRCAP_REG_RW_FAIL_RW_HCCTL2_A,
                HRCAP_REG_RW_FAIL_RW_HCCTL2_B);

    check_force_clear(&HRCap1Regs, &g_hcifr1_forced, &g_hcifr1_cleared,
                      &g_hciclr1_readback, &g_hcifrc1_readback,
                      HRCAP_REG_RW_FAIL_FORCE1,
                      HRCAP_REG_RW_FAIL_GLOBAL_INT1,
                      HRCAP_REG_RW_FAIL_CLEAR1,
                      HRCAP_REG_RW_FAIL_ACTION_READ1);
    check_force_clear(&HRCap2Regs, &g_hcifr2_forced, &g_hcifr2_cleared,
                      &g_hciclr2_readback, &g_hcifrc2_readback,
                      HRCAP_REG_RW_FAIL_FORCE2,
                      HRCAP_REG_RW_FAIL_GLOBAL_INT2,
                      HRCAP_REG_RW_FAIL_CLEAR2,
                      HRCAP_REG_RW_FAIL_ACTION_READ2);

    clear_all_flags(&HRCap1Regs);
    clear_all_flags(&HRCap2Regs);
    test_runtime_pass();
}
