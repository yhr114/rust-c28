//###########################################################################
//  FILE:  watchdog_intr_mode_test/main.c
//  TITLE: Watchdog Interrupt Mode Test
//  DESC:  Verify watchdog timeout generates WAKEINT in interrupt mode and
//         software continues executing without entering reset flow.
//         This case does not check WDFLAG semantics.
//###########################################################################
#include "DSP28x_Project.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

#define WD_INT_TIMEOUT_US  20000U

volatile Uint32 g_wake_count = 0U;

__interrupt void wakeint_isr(void)
{
    g_wake_count++;

    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    PieCtrlRegs.PIEACK.all = 0x0001;
}

static Uint16 wait_for_wakeint(Uint32 timeout_us)
{
    while (timeout_us--)
    {
        if (g_wake_count != 0U)
        {
            return 1U;
        }
        DELAY_US(1);
    }

    return 0U;
}

void main(void)
{
    InitSysCtrl();
    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();

    EALLOW;
    PieVectTable.WAKEINT = &wakeint_isr;
    EDIS;

    PieCtrlRegs.PIECTRL.bit.ENPIE = 1;
    PieCtrlRegs.PIEIER1.bit.INTx8 = 1;
    IER |= 0x0001;
    EINT;

    EALLOW;
    SysCtrlRegs.SCSR = 0x02;
    SysCtrlRegs.WDCR = 0x28;
    EDIS;

    if (!wait_for_wakeint(WD_INT_TIMEOUT_US))
    {
        fail(1U);
    }

    pass();
}
