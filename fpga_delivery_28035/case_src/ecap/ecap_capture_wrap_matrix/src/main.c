#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_capture_wrap_matrix only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_wrap_cap_log[20][4];
volatile Uint16 g_wrap_flag_log[20];
volatile Uint16 g_wrap_stage_log[20];
volatile Uint16 g_ecap_stim_stage;

static void config_ecap1_input_on_gpio19(void)
{
    EALLOW;

    /*
     * ECAP1 input path:
     *   UVM capture_matrix stimulus -> GPIO19 pad -> GPAMUX2.GPIO19 = 3 -> ECAP1.
     * C changes g_ecap_stim_stage; UVM polls it through tb_mem_backdoor_if and
     * changes the free-running low/high segment lengths.
     */
    GpioCtrlRegs.GPAPUD.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO19 = 0U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO19 = 3U;

    EDIS;
}

static Uint16 event_mask(Uint16 stop_wrap)
{
    Uint16 count = (Uint16)(stop_wrap + 1U);
    return (Uint16)(0x0001U | (((1U << count) - 1U) << 1U));
}

static void clear_capture_flags(void)
{
    ECap1Regs.ECCLR.all = 0x001FU;
}

static void set_stage(Uint16 stage_id, Uint16 slot)
{
    g_ecap_stim_stage = stage_id;
    g_wrap_stage_log[slot] = stage_id;
    board_delay_us(ECAP_WRAP_STAGE_SETTLE_US);
}

static void set_idle_stage(Uint16 active_stage, Uint16 slot)
{
    g_ecap_stim_stage = (Uint16)(ECAP_WRAP_STAGE_IDLE_BASE + active_stage);
    g_wrap_stage_log[slot] = g_ecap_stim_stage;
    board_delay_us(ECAP_WRAP_STAGE_SETTLE_US);
}

static void init_capture(Uint16 one_shot, Uint16 stop_wrap)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;

    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 0U;
    ECap1Regs.ECEINT.all = 0U;
    clear_capture_flags();

    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.CTRPHS = 0UL;
    ECap1Regs.CAP1 = 0UL;
    ECap1Regs.CAP2 = 0UL;
    ECap1Regs.CAP3 = 0UL;
    ECap1Regs.CAP4 = 0UL;
    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = 0U;

    ECap1Regs.ECCTL1.bit.CAP1POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP2POL = 1U;
    ECap1Regs.ECCTL1.bit.CAP3POL = 0U;
    ECap1Regs.ECCTL1.bit.CAP4POL = 1U;
    ECap1Regs.ECCTL1.bit.CTRRST1 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST2 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST3 = 0U;
    ECap1Regs.ECCTL1.bit.CTRRST4 = 0U;
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;

    ECap1Regs.ECCTL2.bit.CONT_ONESHT = one_shot;
    ECap1Regs.ECCTL2.bit.STOP_WRAP = stop_wrap;
    ECap1Regs.ECCTL2.bit.CAP_APWM = 0U;
    ECap1Regs.ECCTL2.bit.SYNCI_EN = 0U;
    ECap1Regs.ECCTL2.bit.SYNCO_SEL = 0U;

    ECap1Regs.ECEINT.bit.CEVT1 = 1U;
    ECap1Regs.ECEINT.bit.CEVT2 = 1U;
    ECap1Regs.ECEINT.bit.CEVT3 = 1U;
    ECap1Regs.ECEINT.bit.CEVT4 = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    ECap1Regs.ECCTL2.bit.TSCTRSTOP = 1U;
}

static void snapshot_caps(Uint16 slot)
{
    g_wrap_flag_log[slot] = ECap1Regs.ECFLG.all;
    g_wrap_cap_log[slot][0] = ECap1Regs.CAP1;
    g_wrap_cap_log[slot][1] = ECap1Regs.CAP2;
    g_wrap_cap_log[slot][2] = ECap1Regs.CAP3;
    g_wrap_cap_log[slot][3] = ECap1Regs.CAP4;
}

static void wait_flags(Uint16 mask, Uint16 fail_code)
{
    Uint32 timeout_us = ECAP_WRAP_WAIT_US;

    while (timeout_us-- != 0UL) {
        if ((ECap1Regs.ECFLG.all & mask) == mask) {
            return;
        }
        board_delay_us(1UL);
    }

    test_runtime_fail(fail_code);
}

static void check_captured_order(Uint16 slot, Uint16 count, Uint16 zero_fail, Uint16 order_fail)
{
    Uint16 idx;

    for (idx = 0U; idx < count; idx++) {
        if (g_wrap_cap_log[slot][idx] == 0UL) {
            test_runtime_fail(zero_fail);
        }
    }

    for (idx = 1U; idx < count; idx++) {
        if (g_wrap_cap_log[slot][idx] <= g_wrap_cap_log[slot][idx - 1U]) {
            test_runtime_fail(order_fail);
        }
    }
}

static Uint16 caps_changed(Uint16 lhs_slot, Uint16 rhs_slot, Uint16 count)
{
    Uint16 idx;

    for (idx = 0U; idx < count; idx++) {
        if (g_wrap_cap_log[lhs_slot][idx] != g_wrap_cap_log[rhs_slot][idx]) {
            return 1U;
        }
    }
    return 0U;
}

static Uint16 caps_match_live(Uint16 slot, Uint16 count)
{
    Uint16 idx;
    Uint32 live_caps[4];

    live_caps[0] = ECap1Regs.CAP1;
    live_caps[1] = ECap1Regs.CAP2;
    live_caps[2] = ECap1Regs.CAP3;
    live_caps[3] = ECap1Regs.CAP4;
    for (idx = 0U; idx < count; idx++) {
        if (live_caps[idx] != g_wrap_cap_log[slot][idx]) {
            return 0U;
        }
    }
    return 1U;
}

static void check_unused_caps_zero(Uint16 slot, Uint16 count)
{
    Uint16 idx;

    for (idx = count; idx < 4U; idx++) {
        if (g_wrap_cap_log[slot][idx] != 0UL) {
            test_runtime_fail(ECAP_WRAP_FAIL_ONESHOT_EXTRA);
        }
    }
}

static void run_oneshot_stop(Uint16 stop_wrap)
{
    Uint16 count = (Uint16)(stop_wrap + 1U);
    Uint16 slot = stop_wrap;
    Uint16 mask = event_mask(stop_wrap);
    Uint32 cap_snapshot[4];
    Uint16 idx;
    Uint16 stage = (Uint16)(ECAP_WRAP_STAGE_ONESHOT0 + stop_wrap);

    set_idle_stage(stage, slot);
    init_capture(1U, stop_wrap);
    set_stage(stage, slot);
    wait_flags(mask, ECAP_WRAP_FAIL_ONESHOT_TIMEOUT);
    snapshot_caps(slot);

    if (ECap1Regs.ECCTL1.bit.CAPLDEN != 0U) {
        test_runtime_fail(ECAP_WRAP_FAIL_CAPLDEN_NOT_CLEARED);
    }

    check_captured_order(slot,
                         count,
                         ECAP_WRAP_FAIL_ONESHOT_ZERO,
                         ECAP_WRAP_FAIL_ONESHOT_ORDER);
    check_unused_caps_zero(slot, count);
    if ((g_wrap_flag_log[slot] & (Uint16)(0x001FU & (~mask))) != 0U) {
        test_runtime_fail(ECAP_WRAP_FAIL_ONESHOT_EXTRA);
    }

    for (idx = 0U; idx < 4U; idx++) {
        cap_snapshot[idx] = g_wrap_cap_log[slot][idx];
    }
    board_delay_us(ECAP_WRAP_STABILITY_US);
    if ((ECap1Regs.CAP1 != cap_snapshot[0]) ||
        (ECap1Regs.CAP2 != cap_snapshot[1]) ||
        (ECap1Regs.CAP3 != cap_snapshot[2]) ||
        (ECap1Regs.CAP4 != cap_snapshot[3])) {
        test_runtime_fail(ECAP_WRAP_FAIL_ONESHOT_CHANGED);
    }
}

static void run_rearm_stop(Uint16 stop_wrap)
{
    Uint16 count = (Uint16)(stop_wrap + 1U);
    Uint16 first_slot = (Uint16)(4U + stop_wrap);
    Uint16 second_slot = (Uint16)(8U + stop_wrap);
    Uint16 mask = event_mask(stop_wrap);
    Uint16 stage = (Uint16)(ECAP_WRAP_STAGE_REARM0 + stop_wrap);

    set_idle_stage(stage, first_slot);
    init_capture(1U, stop_wrap);
    set_stage(stage, first_slot);
    wait_flags(mask, ECAP_WRAP_FAIL_REARM_TIMEOUT);
    snapshot_caps(first_slot);
    check_captured_order(first_slot,
                         count,
                         ECAP_WRAP_FAIL_ONESHOT_ZERO,
                         ECAP_WRAP_FAIL_ONESHOT_ORDER);
    if (ECap1Regs.ECCTL1.bit.CAPLDEN != 0U) {
        test_runtime_fail(ECAP_WRAP_FAIL_CAPLDEN_NOT_CLEARED);
    }

    /* REARM alone restarts the event sequencer but leaves CAP loading gated. */
    set_idle_stage(stage, second_slot);
    clear_capture_flags();
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    set_stage(stage, second_slot);
    wait_flags(mask, ECAP_WRAP_FAIL_REARM_TIMEOUT);
    if (ECap1Regs.ECCTL1.bit.CAPLDEN != 0U) {
        test_runtime_fail(ECAP_WRAP_FAIL_REARM_CAPLDEN_SET);
    }
    if (!caps_match_live(first_slot, count)) {
        test_runtime_fail(ECAP_WRAP_FAIL_REARM_NO_CAPLDEN_LOAD);
    }

    /* CAPLDEN must be restored explicitly before REARM can reload CAPx. */
    clear_capture_flags();
    ECap1Regs.ECCTL1.bit.CAPLDEN = 1U;
    ECap1Regs.ECCTL2.bit.REARM = 1U;
    set_stage(stage, second_slot);
    wait_flags(mask, ECAP_WRAP_FAIL_REARM_RECOVERY);
    snapshot_caps(second_slot);
    check_captured_order(second_slot,
                         count,
                         ECAP_WRAP_FAIL_ONESHOT_ZERO,
                         ECAP_WRAP_FAIL_ONESHOT_ORDER);

    if (!caps_changed(first_slot, second_slot, count)) {
        test_runtime_fail(ECAP_WRAP_FAIL_REARM_NOT_UPDATED);
    }
}

static void run_continuous_wrap(Uint16 stop_wrap)
{
    Uint16 count = (Uint16)(stop_wrap + 1U);
    Uint16 first_slot = (Uint16)(12U + stop_wrap);
    Uint16 second_slot = (Uint16)(first_slot + 4U);
    Uint16 mask = event_mask(stop_wrap);
    Uint16 stage = (Uint16)(ECAP_WRAP_STAGE_CONT0 + stop_wrap);

    set_idle_stage(stage, first_slot);
    init_capture(0U, stop_wrap);
    set_stage(stage, first_slot);
    wait_flags(mask, ECAP_WRAP_FAIL_CONT_FIRST);
    snapshot_caps(first_slot);
    check_captured_order(first_slot,
                         count,
                         ECAP_WRAP_FAIL_CONT_ZERO,
                         ECAP_WRAP_FAIL_CONT_ORDER);

    clear_capture_flags();
    wait_flags(mask, ECAP_WRAP_FAIL_CONT_SECOND);
    snapshot_caps(second_slot);
    check_captured_order(second_slot,
                         count,
                         ECAP_WRAP_FAIL_CONT_ZERO,
                         ECAP_WRAP_FAIL_CONT_ORDER);

    if (!caps_changed(first_slot, second_slot, count)) {
        test_runtime_fail(ECAP_WRAP_FAIL_CONT_NOT_UPDATED);
    }
}

void main(void)
{
    Uint16 stop_wrap;

    board_demo_init();
    config_ecap1_input_on_gpio19();

    for (stop_wrap = 0U; stop_wrap < 4U; stop_wrap++) {
        run_oneshot_stop(stop_wrap);
    }

    for (stop_wrap = 0U; stop_wrap < 4U; stop_wrap++) {
        run_rearm_stop(stop_wrap);
    }

    for (stop_wrap = 0U; stop_wrap < 4U; stop_wrap++) {
        run_continuous_wrap(stop_wrap);
    }

    test_runtime_pass();
}
