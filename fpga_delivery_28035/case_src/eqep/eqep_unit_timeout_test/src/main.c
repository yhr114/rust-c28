#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define mark(stage) do { g_test_runtime_fail_code = (stage); } while (0)

static void eqep_unit_gpio_init(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

static void eqep_unit_clear_flags(void)
{
    EQep1Regs.QCLR.all = 0x0FFFU;
    EQep1Regs.QCLR.bit.INT = 1U;
    EQep1Regs.QEPSTS.all = 0x00F0U;
}

static void eqep_unit_reset(void)
{
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.all  = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QEINT.all   = 0x0000U;

    eqep_unit_clear_flags();

    EQep1Regs.QPOSMAX = 0xFFFFFFFFUL;
    EQep1Regs.QPOSCNT = 0UL;
    EQep1Regs.QUPRD   = 0UL;
}

static Uint16 wait_qutmr_activity(Uint32 timeout)
{
    Uint32 start_timer = EQep1Regs.QUTMR;

    while (timeout > 0UL) {
        if (EQep1Regs.QUTMR != start_timer) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static Uint16 wait_uto_flag(Uint32 timeout)
{
    while (timeout > 0UL) {
        if (EQep1Regs.QFLG.bit.UTO != 0U) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static Uint16 wait_eqep_int_flag(Uint32 timeout)
{
    while (timeout > 0UL) {
        if (EQep1Regs.QFLG.bit.INT != 0U) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static Uint16 wait_no_uto_flag(Uint32 window)
{
    while (window > 0UL) {
        if (EQep1Regs.QFLG.bit.UTO != 0U) {
            return 0U;
        }
        window--;
    }
    return 1U;
}

static void hold_control_cov(Uint16 pcrm, Uint16 qpen, Uint16 ute, Uint16 wde)
{
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QEPCTL.bit.PCRM = pcrm;
    EQep1Regs.QEPCTL.bit.UTE  = ute;
    EQep1Regs.QEPCTL.bit.WDE  = wde;
    EQep1Regs.QWDPRD = 0xFFFFU;
    EQep1Regs.QUPRD  = 0xFFFFFFFFUL;
    EQep1Regs.QEPCTL.bit.QPEN = qpen;
    DELAY_US(EQEP_UTO_COV_HOLD_US);
}

static void run_quprd_readback_stage(void)
{
    mark(EQEP_UTO_STAGE_QUPRD);
    eqep_unit_reset();

    EQep1Regs.QUPRD = EQEP_UTO_PRD_SHORT;
    if (EQep1Regs.QUPRD != EQEP_UTO_PRD_SHORT) {
        fail(EQEP_UTO_FAIL_QUPRD_READBACK);
    }

    EQep1Regs.QUPRD = EQEP_UTO_PRD_IRQ;
    if (EQep1Regs.QUPRD != EQEP_UTO_PRD_IRQ) {
        fail(EQEP_UTO_FAIL_QUPRD_READBACK);
    }
}

static void check_qutmr_write(Uint32 value)
{
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QEPCTL.bit.UTE = 0U;
    EQep1Regs.QUTMR = value;

    if (EQep1Regs.QUTMR != value) {
        fail(EQEP_UTO_FAIL_QUTMR_READBACK);
    }
}

static void run_qutmr_write_stage(void)
{
    mark(EQEP_UTO_STAGE_QUTMR);
    eqep_unit_reset();

    check_qutmr_write(0x00000000UL);
    check_qutmr_write(0x000000FFUL);
    check_qutmr_write(0x0000FF00UL);
    check_qutmr_write(0x00FF0000UL);
    check_qutmr_write(0xFF000000UL);
    check_qutmr_write(0xA5A55A5AUL);
    check_qutmr_write(0x5A5AA5A5UL);
    check_qutmr_write(0x00000000UL);
}

static void run_uto_flag_stage(void)
{
    mark(EQEP_UTO_STAGE_FLAG);
    eqep_unit_reset();

    EQep1Regs.QUPRD = EQEP_UTO_PRD_SHORT;
    EQep1Regs.QEINT.bit.UTO = 0U;
    EQep1Regs.QEPCTL.bit.PCRM = 3U;
    EQep1Regs.QEPCTL.bit.UTE = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_qutmr_activity(EQEP_UTO_POLL_TIMEOUT) == 0U) {
        fail(EQEP_UTO_FAIL_TIMER_STATIC);
    }

    if (wait_uto_flag(EQEP_UTO_POLL_TIMEOUT) == 0U) {
        fail(EQEP_UTO_FAIL_FLAG_TIMEOUT);
    }

    EQep1Regs.QCLR.bit.UTO = 1U;
    EQep1Regs.QCLR.bit.INT = 1U;
    if (EQep1Regs.QFLG.bit.UTO != 0U) {
        fail(EQEP_UTO_FAIL_CLEAR_UTO);
    }
}

static void run_uto_interrupt_stage(void)
{
    mark(EQEP_UTO_STAGE_IRQ);
    eqep_unit_reset();

    EQep1Regs.QUPRD = EQEP_UTO_PRD_IRQ;
    EQep1Regs.QEINT.bit.UTO = 1U;
    EQep1Regs.QEPCTL.bit.PCRM = 3U;
    EQep1Regs.QEPCTL.bit.UTE = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_uto_flag(EQEP_UTO_POLL_TIMEOUT) == 0U) {
        fail(EQEP_UTO_FAIL_IRQ_FLAG_TIMEOUT);
    }

    if (wait_eqep_int_flag(EQEP_UTO_INT_WINDOW) == 0U) {
        fail(EQEP_UTO_FAIL_IRQ_TIMEOUT);
    }

    if (EQep1Regs.QFLG.bit.INT == 0U || EQep1Regs.QFLG.bit.UTO == 0U) {
        fail(EQEP_UTO_FAIL_IRQ_SOURCE);
    }

    EQep1Regs.QCLR.bit.UTO = 1U;
    EQep1Regs.QCLR.bit.INT = 1U;
}

static void run_ute_disable_stage(void)
{
    mark(EQEP_UTO_STAGE_UTE_DISABLE);
    eqep_unit_reset();

    EQep1Regs.QUPRD = EQEP_UTO_PRD_QUIET;
    EQep1Regs.QEPCTL.bit.PCRM = 3U;
    EQep1Regs.QEPCTL.bit.UTE = 0U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_no_uto_flag(EQEP_UTO_QUIET_WINDOW) == 0U) {
        fail(EQEP_UTO_FAIL_DISABLE_LEAK);
    }
}

static void run_control_cross_stage(void)
{
    mark(EQEP_UTO_STAGE_CONTROL_CROSS);
    eqep_unit_reset();

    hold_control_cov(3U, 0U, 1U, 0U);
    hold_control_cov(2U, 0U, 1U, 0U);
    hold_control_cov(3U, 1U, 0U, 0U);
    hold_control_cov(2U, 1U, 0U, 0U);
    hold_control_cov(3U, 1U, 1U, 1U);
    hold_control_cov(2U, 1U, 1U, 1U);
    hold_control_cov(1U, 1U, 1U, 1U);

    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QEPCTL.bit.UTE = 0U;
    EQep1Regs.QEPCTL.bit.WDE = 0U;
}

void main(void)
{
    InitSysCtrl();
    eqep_unit_gpio_init();

    DINT;
    InitPieCtrl();
    IER = 0x0000U;
    IFR = 0x0000U;
    InitPieVectTable();

    run_quprd_readback_stage();
    run_qutmr_write_stage();
    run_uto_flag_stage();
    run_uto_interrupt_stage();
    run_ute_disable_stage();
    run_control_cross_stage();

    mark(EQEP_UTO_STAGE_PASS);
    pass();

    while (1) {
    }
}
