// =============================================================
// eqep_count_basic — Basic quadrature count smoke
// Waits for the default UVM encoder to drive quadrature edges and
// verifies QPOSCNT responds. Direction is covered by mode-specific tests.
// =============================================================
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

static void init_eqep1(void)
{
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QPOSMAX = 0xFFFFFFFFUL;
    EQep1Regs.QPOSINIT = 0UL;
    EQep1Regs.QPOSCNT = 0UL;

    EQep1Regs.QEPCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.bit.PCRM = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;
}

void main(void)
{
    unsigned long timeout;
    unsigned long start_cnt;

    InitSysCtrl();
    InitEQep1Gpio();

    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();

    init_eqep1();

    start_cnt = EQep1Regs.QPOSCNT;
    timeout = EQEP_COUNT_BASIC_POLL_TIMEOUT;
    while (EQep1Regs.QPOSCNT == start_cnt && timeout > 0UL) {
        --timeout;
    }

    if (timeout == 0UL) {
        fail(EQEP_COUNT_BASIC_FAIL_NO_COUNT);
    } else {
        pass();
    }

    while (1) {
    }
}
