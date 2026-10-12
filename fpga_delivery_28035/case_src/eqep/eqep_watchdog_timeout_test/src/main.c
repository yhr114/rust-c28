#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()

static void eqep_watchdog_gpio_init(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

static void eqep_clear_flags(void)
{
    EQep1Regs.QCLR.all = 0x0FFFU;
    EQep1Regs.QCLR.bit.INT = 1U;
    EQep1Regs.QEPSTS.all = 0x00F0U;
}

static void eqep_watchdog_reset(void)
{
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.all  = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QEINT.all   = 0x0000U;

    eqep_clear_flags();

    EQep1Regs.QPOSMAX = 0xFFFFFFFFUL;
    EQep1Regs.QPOSCNT = 0UL;
    EQep1Regs.QWDPRD  = 0U;
}

static Uint16 wait_wto_flag(Uint32 timeout)
{
    while (timeout > 0UL) {
        if (EQep1Regs.QFLG.bit.WTO != 0U) {
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

static Uint16 wait_no_wto_flag(Uint32 window)
{
    while (window > 0UL) {
        if (EQep1Regs.QFLG.bit.WTO != 0U) {
            return 0U;
        }
        window--;
    }
    return 1U;
}

static void run_wdprd_readback_stage(void)
{
    eqep_watchdog_reset();

    EQep1Regs.QWDPRD = EQEP_WDTOG_PRD_SHORT;
    if (EQep1Regs.QWDPRD != EQEP_WDTOG_PRD_SHORT) {
        fail(EQEP_WDTOG_FAIL_WDPRD_READBACK);
    }

    EQep1Regs.QWDPRD = EQEP_WDTOG_PRD_IRQ;
    if (EQep1Regs.QWDPRD != EQEP_WDTOG_PRD_IRQ) {
        fail(EQEP_WDTOG_FAIL_WDPRD_READBACK);
    }
}

static void run_wto_flag_stage(void)
{
    Uint16 start_timer;

    eqep_watchdog_reset();

    EQep1Regs.QWDPRD = EQEP_WDTOG_PRD_SHORT;
    EQep1Regs.QEINT.bit.WTO = 0U;
    EQep1Regs.QEPCTL.bit.WDE = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;
    start_timer = EQep1Regs.QWDTMR;

    if (wait_wto_flag(EQEP_WDTOG_POLL_TIMEOUT) == 0U) {
        fail(EQEP_WDTOG_FAIL_FLAG_TIMEOUT);
    }

    if (EQep1Regs.QWDTMR == start_timer) {
        fail(EQEP_WDTOG_FAIL_TIMER_STATIC);
    }

    EQep1Regs.QCLR.bit.WTO = 1U;
    EQep1Regs.QCLR.bit.INT = 1U;
    if (EQep1Regs.QFLG.bit.WTO != 0U) {
        fail(EQEP_WDTOG_FAIL_CLEAR_WTO);
    }
}

static void run_wto_interrupt_stage(void)
{
    eqep_watchdog_reset();

    EQep1Regs.QWDPRD = EQEP_WDTOG_PRD_IRQ;
    EQep1Regs.QEINT.bit.WTO = 1U;
    EQep1Regs.QEPCTL.bit.WDE = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_wto_flag(EQEP_WDTOG_POLL_TIMEOUT) == 0U) {
        fail(EQEP_WDTOG_FAIL_IRQ_FLAG_TIMEOUT);
    }

    if (wait_eqep_int_flag(EQEP_WDTOG_IRQ_WINDOW) == 0U) {
        fail(EQEP_WDTOG_FAIL_IRQ_TIMEOUT);
    }

    if (EQep1Regs.QFLG.bit.INT == 0U || EQep1Regs.QFLG.bit.WTO == 0U) {
        fail(EQEP_WDTOG_FAIL_IRQ_SOURCE);
    }

    EQep1Regs.QCLR.bit.WTO = 1U;
    EQep1Regs.QCLR.bit.INT = 1U;
}

static void run_wde_disable_stage(void)
{
    eqep_watchdog_reset();

    EQep1Regs.QWDPRD = EQEP_WDTOG_PRD_SHORT;
    EQep1Regs.QEPCTL.bit.WDE = 0U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;

    if (wait_no_wto_flag(EQEP_WDTOG_QUIET_WINDOW) == 0U) {
        fail(EQEP_WDTOG_FAIL_DISABLE_LEAK);
    }
}

void main(void)
{
    InitSysCtrl();
    eqep_watchdog_gpio_init();

    DINT;
    InitPieCtrl();
    IER = 0x0000U;
    IFR = 0x0000U;
    InitPieVectTable();

    run_wdprd_readback_stage();
    run_wto_flag_stage();
    run_wto_interrupt_stage();
    run_wde_disable_stage();

    pass();

    while (1) {
    }
}
