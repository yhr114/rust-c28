#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "test_runtime.h"

volatile Uint16 g_hrcap_stim_stage;
volatile Uint16 g_hrcap_clock_ctl1;
volatile Uint16 g_hrcap_clock_ctl2;
volatile Uint16 g_hrcap_clock_flags1;
volatile Uint16 g_hrcap_clock_flags2;
volatile Uint16 g_hrcap_clock_counter_before_disable;
volatile Uint16 g_hrcap_clock_counter_off_read1;
volatile Uint16 g_hrcap_clock_counter_off_read2;
volatile Uint16 g_hrcap_clock_counter_after_enable;
volatile Uint16 g_hrcap_clock_counter_before_disable2;
volatile Uint16 g_hrcap_clock_counter_after_enable2;

#define HRCAP_STAGE_CLOCK_RUNNING   6U
#define HRCAP_STAGE_CLOCK_DISABLED  7U
#define HRCAP_STAGE_CLOCK_REENABLED 8U
#define HRCAP_STAGE_CLOCK_RUNNING2  9U
#define HRCAP_STAGE_CLOCK_DISABLED2 10U
#define HRCAP_STAGE_CLOCK_REENABLED2 11U

/*
 * Keep the gate probes away from a natural 16-bit wrap.  This makes a small
 * forward delta after re-enable an unambiguous continuation, while a reset
 * to zero produces a large modulo delta and fails the probe.
 */
#define HRCAP_PROBE_COUNTER_MIN      0x1000U
#define HRCAP_PROBE_COUNTER_MAX      0xC000U
#define HRCAP_CONTINUE_MAX_DELTA     0x1000U

static void wait_software_cycles(Uint32 count)
{
    volatile Uint32 index;

    for (index = 0UL; index < count; ++index) {
        /* Volatile loop: allow peripheral clock and bus writes to settle. */
    }
}

static Uint16 counter_in_probe_window(Uint16 counter)
{
    return ((counter >= HRCAP_PROBE_COUNTER_MIN) &&
            (counter <= HRCAP_PROBE_COUNTER_MAX));
}

static Uint16 wait_for_counter_continuation(Uint16 frozen_counter,
                                            volatile Uint16 *sample)
{
    Uint32 limit;
    Uint16 delta;

    for (limit = 0UL; limit < 100000UL; ++limit) {
        *sample = HRCap1Regs.HCCOUNTER;
        delta = (Uint16)(*sample - frozen_counter);
        if (delta != 0U)
            return (delta <= HRCAP_CONTINUE_MAX_DELTA);
    }

    return 0U;
}

static Uint16 verify_clock_disable_read_and_continue(void)
{
    Uint32 limit;
    Uint16 fail_code = 0U;

    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_RUNNING;
    g_hrcap_clock_counter_before_disable = 0U;
    for (limit = 0UL; limit < 100000UL; ++limit) {
        g_hrcap_clock_counter_before_disable = HRCap1Regs.HCCOUNTER;
        if (counter_in_probe_window(g_hrcap_clock_counter_before_disable))
            break;
    }
    if (!counter_in_probe_window(g_hrcap_clock_counter_before_disable))
        fail_code = 0x6320U;

    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = 0U;
    EDIS;
    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_DISABLED;
    wait_software_cycles(1024UL);

    /*
     * SPRUI10A 5.5.5 requires HCCOUNTER to be read only after the HRCAP
     * clock is disabled.  Two reads must therefore expose the same frozen,
     * non-zero counter value rather than a clock-gate-dependent zero.
     */
    g_hrcap_clock_counter_off_read1 = HRCap1Regs.HCCOUNTER;
    wait_software_cycles(256UL);
    g_hrcap_clock_counter_off_read2 = HRCap1Regs.HCCOUNTER;

    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = 1U;
    EDIS;
    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_REENABLED;
    if (!wait_for_counter_continuation(g_hrcap_clock_counter_off_read2,
                                       &g_hrcap_clock_counter_after_enable))
        fail_code = 0x6323U;

    /* Finish both probes before stopping so the UVM continuation checker runs. */
    if (fail_code == 0U) {
        if ((g_hrcap_clock_counter_off_read1 == 0U) ||
            (g_hrcap_clock_counter_off_read2 == 0U))
            fail_code = 0x6321U;
        else if (g_hrcap_clock_counter_off_read1 !=
                 g_hrcap_clock_counter_off_read2)
            fail_code = 0x6322U;
    }

    /*
     * Repeat the complete gate/re-enable sequence.  UVM must observe two
     * independent freeze/continue events, not a one-time artifact.
     */
    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_RUNNING2;
    g_hrcap_clock_counter_before_disable2 = 0U;
    for (limit = 0UL; limit < 100000UL; ++limit) {
        g_hrcap_clock_counter_before_disable2 = HRCap1Regs.HCCOUNTER;
        if (counter_in_probe_window(g_hrcap_clock_counter_before_disable2))
            break;
    }
    if (!counter_in_probe_window(g_hrcap_clock_counter_before_disable2))
        fail_code = 0x6324U;

    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = 0U;
    EDIS;
    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_DISABLED2;
    wait_software_cycles(1024UL);

    EALLOW;
    SysCtrlRegs.PCLKCR2.bit.HRCAP1ENCLK = 1U;
    EDIS;
    g_hrcap_stim_stage = HRCAP_STAGE_CLOCK_REENABLED2;

    if (!wait_for_counter_continuation(g_hrcap_clock_counter_before_disable2,
                                       &g_hrcap_clock_counter_after_enable2))
        fail_code = 0x6325U;

    return fail_code;
}

static void verify_one(volatile struct HRCAP_REGS *regs, Uint16 fail_base,
                       volatile Uint16 *ctl_snapshot,
                       volatile Uint16 *flag_snapshot)
{
    hrcap_case_config(regs, 0x010EU);
    hrcap_case_force(regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL);
    if (!hrcap_case_wait_set(regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL, 10000UL))
        test_runtime_fail(fail_base + 1U);
    hrcap_case_softreset(regs, 0x010EU);
    *ctl_snapshot = regs->HCCTL.all;
    *flag_snapshot = regs->HCIFR.all;
    if ((*ctl_snapshot & HRCAP_CASE_CTL_MASK) != 0x010EU)
        test_runtime_fail(fail_base + 2U);
    if ((*flag_snapshot & HRCAP_CASE_FLAG_ALL) != 0U)
        test_runtime_fail(fail_base + 3U);
}

void main(void)
{
    Uint16 clock_fail_code;

    board_demo_init();
    hrcap_case_enable_clocks();
    hrcap_case_select_default_pads();
    g_hrcap_stim_stage = HRCAP_STAGE_CONFIGURED;
    verify_one(&HRCap1Regs, 0x6300U, &g_hrcap_clock_ctl1, &g_hrcap_clock_flags1);
    verify_one(&HRCap2Regs, 0x6310U, &g_hrcap_clock_ctl2, &g_hrcap_clock_flags2);
    clock_fail_code = verify_clock_disable_read_and_continue();
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    if (clock_fail_code != 0U)
        test_runtime_fail(clock_fail_code);
    test_runtime_pass();
}
