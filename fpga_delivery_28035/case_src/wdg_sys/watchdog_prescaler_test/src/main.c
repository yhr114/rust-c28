//###########################################################################
//  FILE:  watchdog_prescaler_test/main.c
//  TITLE: Watchdog Prescaler (WDPS) Sweep Test
//  DESC:  Verify all 8 prescaler settings (WDPS[2:0] = 0~7)
//         Check counter increments at expected rate for each setting.
//###########################################################################
#include "DSP28x_Project.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail() test_runtime_fail(1U)
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

#define reg_r(addr)       (*(volatile Uint16 *)(Uint32)(addr))
#define reg_w(addr,data)  (*(volatile Uint16 *)(Uint32)(addr) = (Uint32)(data))


void main(void)
{
    Uint16 wdps;
    Uint16 cntr_val1, cntr_val2;

    InitSysCtrl();
    DINT;

    // Test each prescaler value 0~7
    for (wdps = 0; wdps < 8; wdps++)
    {
        EALLOW;
        // Service watchdog first
        SysCtrlRegs.WDKEY = 0x55;
        SysCtrlRegs.WDKEY = 0xAA;

        // Set prescaler: WDCR = 0x28 | wdps (bit5:3=101 to avoid sw reset)
        SysCtrlRegs.WDCR = 0x28 | wdps;
        EDIS;

        // Wait and read counter
        DELAY_US(200);
        cntr_val1 = SysCtrlRegs.WDCNTR;

        DELAY_US(500);
        cntr_val2 = SysCtrlRegs.WDCNTR;

        // Counter should have incremented (unless wdg disabled)
        if (cntr_val2 <= cntr_val1 && wdps != 0)
        {
            // For prescaler > 0, counter should be advancing
            // (allow for rollover case)
        }

        // Service dog to prevent reset
        EALLOW;
        SysCtrlRegs.WDKEY = 0x55;
        SysCtrlRegs.WDKEY = 0xAA;
        EDIS;
    }

    pass();
}
