//###########################################################################
//  FILE:  watchdog_wdflag_test/main.c
//  TITLE: Watchdog WDINT Status Test
//  DESC:  Verify watchdog interrupt mode asserts WAKEINT and software can
//         service the watchdog after the interrupt event.
//###########################################################################
#include "DSP28x_Project.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

#define WD_EVENT_TIMEOUT_US  20000U

__interrupt void wakeint_isr(void);

volatile Uint32 WakeCount = 0;

static Uint16 wait_for_wakeint(Uint32 timeout_us)
{
    while (timeout_us--)
    {
        if (WakeCount != 0U)
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

    // Enable WAKEINT: PIE Group 1, INT8
    PieCtrlRegs.PIECTRL.bit.ENPIE = 1;
    PieCtrlRegs.PIEIER1.bit.INTx8 = 1;
    IER |= 0x0001;
    EINT;

    // Interrupt mode: timeout should assert WDINT/WAKEINT, not reset the device.
    EALLOW;
    SysCtrlRegs.SCSR = 0x02;
    SysCtrlRegs.WDCR = 0x28;
    EDIS;

    if (!wait_for_wakeint(WD_EVENT_TIMEOUT_US))
    {
        fail(1U);
    }

    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    pass();
}

__interrupt void wakeint_isr(void)
{
    WakeCount++;

    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    PieCtrlRegs.PIEACK.all = 0x0001;
}
