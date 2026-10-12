//###########################################################################
//  FILE:  watchdog_key_sequence_test/main.c
//  TITLE: Watchdog Key Sequence Correctness Test
//  DESC:  Verify that ONLY the correct sequence 0x55->0xAA clears the
//         counter. All other sequences should NOT clear the counter.
//###########################################################################
#include "DSP28x_Project.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

static void service_watchdog(void)
{
    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;
}

void main(void)
{
    Uint16 cntr_before, cntr_after;

    InitSysCtrl();
    DINT;

    EALLOW;
    SysCtrlRegs.WDCR = 0x28;
    EDIS;

    service_watchdog();

    // ---- Test 1: Wrong sequence 0xAA -> 0xAA (should NOT clear) ----
    DELAY_US(200);
    cntr_before = SysCtrlRegs.WDCNTR;

    EALLOW;
    SysCtrlRegs.WDKEY = 0xAA;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    DELAY_US(100);
    cntr_after = SysCtrlRegs.WDCNTR;
    if (cntr_after <= cntr_before)
    {
        fail(1U);
    }
    service_watchdog();

    // ---- Test 2: Wrong sequence 0x55 -> 0x55 (should NOT clear) ----
    DELAY_US(200);
    cntr_before = SysCtrlRegs.WDCNTR;

    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0x55;
    EDIS;

    DELAY_US(100);
    cntr_after = SysCtrlRegs.WDCNTR;
    if (cntr_after <= cntr_before)
    {
        fail(2U);
    }
    service_watchdog();

    // ---- Test 3: Wrong sequence 0xAA -> 0x55 (reversed, should NOT clear) ----
    DELAY_US(200);
    cntr_before = SysCtrlRegs.WDCNTR;

    EALLOW;
    SysCtrlRegs.WDKEY = 0xAA;
    SysCtrlRegs.WDKEY = 0x55;
    EDIS;

    DELAY_US(100);
    cntr_after = SysCtrlRegs.WDCNTR;
    if (cntr_after <= cntr_before)
    {
        fail(3U);
    }

    // ---- Test 4: Correct sequence 0x55 -> 0xAA (SHOULD clear) ----
    DELAY_US(200);
    cntr_before = SysCtrlRegs.WDCNTR;
    service_watchdog();

    DELAY_US(20);
    cntr_after = SysCtrlRegs.WDCNTR;
    if (cntr_after >= cntr_before)
    {
        fail(4U);
    }

    // ---- Test 5: Random value write (should NOT clear) ----
    service_watchdog();
    DELAY_US(200);
    cntr_before = SysCtrlRegs.WDCNTR;

    EALLOW;
    SysCtrlRegs.WDKEY = 0x12;
    SysCtrlRegs.WDKEY = 0x34;
    EDIS;

    DELAY_US(100);
    cntr_after = SysCtrlRegs.WDCNTR;
    if (cntr_after <= cntr_before)
    {
        fail(5U);
    }

    service_watchdog();
    pass();
}
