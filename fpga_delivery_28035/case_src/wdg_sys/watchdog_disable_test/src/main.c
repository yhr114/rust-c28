//###########################################################################
//  FILE:  watchdog_disable_test/main.c
//  TITLE: Watchdog Disable/Enable (WDDIS) Test
//  DESC:  Verify WDDIS bit behavior via WDOVERRIDE mechanism.
//         When WDOVERRIDE=1, WDDIS can be set to disable the watchdog.
//         Once WDOVERRIDE is cleared (locked), WDDIS cannot be changed.
//###########################################################################
#include "DSP28x_Project.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail() test_runtime_fail(1U)
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()


void main(void)
{
    Uint16 cntr1, cntr2;

    InitSysCtrl();
    DINT;

    // ---- Test 1: Disable watchdog via WDDIS ----
    EALLOW;
    // WDOVERRIDE should be 1 after reset, allowing WDDIS write
    // WDCR: bit6=WDDIS=1, bit5:3=101, bit2:0=WDPS
    SysCtrlRegs.WDCR = 0x68; // WDDIS=1, WDPS=0
    EDIS;

    DELAY_US(1000);
    cntr1 = SysCtrlRegs.WDCNTR;
    DELAY_US(1000);
    cntr2 = SysCtrlRegs.WDCNTR;

    // Counter should NOT be incrementing when disabled
    if (cntr2 != cntr1)
    {
        fail();
    }

    // ---- Test 2: Re-enable watchdog ----
    EALLOW;
    SysCtrlRegs.WDCR = 0x28; // WDDIS=0, enable watchdog
    EDIS;

    // Service dog first
    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    DELAY_US(500);
    cntr1 = SysCtrlRegs.WDCNTR;
    DELAY_US(500);
    cntr2 = SysCtrlRegs.WDCNTR;

    // Counter should be incrementing when enabled
    if (cntr2 == cntr1)
    {
        fail();
    }

    // ---- Test 3: Lock WDOVERRIDE by writing SCSR[0]=1 ----
    EALLOW;
    SysCtrlRegs.SCSR = 0x01; // Clear WDOVERRIDE (one-time lock)
    EDIS;

    // Now try to set WDDIS again - should be ignored
    EALLOW;
    SysCtrlRegs.WDCR = 0x68; // Try WDDIS=1
    EDIS;

    // WDDIS should remain 0 since WDOVERRIDE is locked
    if (SysCtrlRegs.WDCR & 0x40)
    {
        fail(); // WDDIS should not be settable after lock
    }

    // Service and pass
    EALLOW;
    SysCtrlRegs.WDKEY = 0x55;
    SysCtrlRegs.WDKEY = 0xAA;
    EDIS;

    pass();
}
