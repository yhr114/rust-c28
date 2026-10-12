#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

static void InitEQep1Gpio(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

static void eqep_base_reset(void)
{
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.all  = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QPOSINIT    = 0UL;
    EQep1Regs.QPOSMAX     = 0xFFFFFFFFUL;
    EQep1Regs.QPOSCNT     = 0UL;
}

static Uint16 wait_count_change(Uint32 start_cnt, Uint32 timeout)
{
    while (timeout > 0UL) {
        if (EQep1Regs.QPOSCNT != start_cnt) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static Uint16 wait_count_ge(Uint32 threshold, Uint32 timeout)
{
    while (timeout > 0UL) {
        if (EQep1Regs.QPOSCNT >= threshold) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static Uint16 run_qsrc_activity_stage(Uint16 qsrc)
{
    Uint32 start_cnt;

    eqep_base_reset();
    EQep1Regs.QDECCTL.bit.QSRC = qsrc;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    start_cnt = EQep1Regs.QPOSCNT;
    if (wait_count_change(start_cnt, EQEP_MODE_TEST_POLL_TIMEOUT) == 0U) {
        return 0U;
    }

    DELAY_US(EQEP_MODE_TEST_STAGE_OBSERVE_US);
    return (EQep1Regs.QPOSCNT != start_cnt) ? 1U : 0U;
}

static Uint16 run_qsrc_up_stage(Uint16 qsrc, Uint32 threshold)
{
    eqep_base_reset();
    EQep1Regs.QDECCTL.bit.QSRC = qsrc;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_count_ge(threshold, EQEP_MODE_TEST_POLL_TIMEOUT) == 0U) {
        return 0U;
    }

    DELAY_US(EQEP_MODE_TEST_STAGE_OBSERVE_US);
    return (EQep1Regs.QPOSCNT >= threshold) ? 1U : 0U;
}

static Uint16 run_qsrc_down_stage(void)
{
    Uint32 start_cnt;

    eqep_base_reset();
    EQep1Regs.QPOSCNT = EQEP_MODE_TEST_DOWN_START;
    EQep1Regs.QDECCTL.bit.QSRC = 3U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    start_cnt = EQep1Regs.QPOSCNT;
    if (wait_count_change(start_cnt, EQEP_MODE_TEST_POLL_TIMEOUT) == 0U) {
        return 0U;
    }

    DELAY_US(EQEP_MODE_TEST_STAGE_OBSERVE_US);
    return (EQep1Regs.QPOSCNT < start_cnt) ? 1U : 0U;
}

static Uint16 run_pcrm_wrap_stage(void)
{
    Uint32 last_cnt;
    Uint32 timeout;

    eqep_base_reset();
    EQep1Regs.QPOSMAX = EQEP_MODE_TEST_WRAP_MAX;
    EQep1Regs.QDECCTL.bit.QSRC = 2U;
    EQep1Regs.QEPCTL.bit.PCRM = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    last_cnt = EQep1Regs.QPOSCNT;
    timeout  = EQEP_MODE_TEST_POLL_TIMEOUT;

    while (timeout > 0UL) {
        Uint32 current_cnt = EQep1Regs.QPOSCNT;

        if (last_cnt >= EQEP_MODE_TEST_WRAP_SEEN_MIN &&
            current_cnt < last_cnt &&
            current_cnt <= EQEP_MODE_TEST_WRAP_RELOAD_MAX) {
            DELAY_US(EQEP_MODE_TEST_STAGE_OBSERVE_US);
            return 1U;
        }

        last_cnt = current_cnt;
        timeout--;
    }

    return 0U;
}

void main(void)
{
    InitSysCtrl();
    InitEQep1Gpio();

    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();

    if (run_qsrc_activity_stage(0U) == 0U) {
        fail(EQEP_MODE_FAIL_QSRC0_ACTIVITY);
    }

    if (run_qsrc_activity_stage(1U) == 0U) {
        fail(EQEP_MODE_FAIL_QSRC1_ACTIVITY);
    }

    if (run_qsrc_up_stage(2U, EQEP_MODE_TEST_UP_MIN_COUNT) == 0U) {
        fail(EQEP_MODE_FAIL_QSRC2_UP);
    }

    if (run_qsrc_down_stage() == 0U) {
        fail(EQEP_MODE_FAIL_QSRC3_DOWN);
    }

    if (run_pcrm_wrap_stage() == 0U) {
        fail(EQEP_MODE_FAIL_PCRM_WRAP);
    }

    pass();

    while (1) {
    }
}
