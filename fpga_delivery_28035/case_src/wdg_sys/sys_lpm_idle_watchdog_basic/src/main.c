#include "board_lpm_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#else
#error Unsupported device for sys_lpm_idle_watchdog_basic
#endif

volatile Uint16 g_sys_lpm_idle_watchdog_basic_count = 0U;

__interrupt void sys_lpm_idle_watchdog_basic_isr(void)
{
    g_sys_lpm_idle_watchdog_basic_count++;
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}

void main(void)
{
    Uint16 iter;

    board_demo_init();

    EALLOW;
    PieVectTable.WAKEINT = &sys_lpm_idle_watchdog_basic_isr;
    EDIS;

    lpm_case_enable_wakeint_irq();
    lpm_case_set_wdint_mode(1U);

    if ((lpm_case_read_scsr() & S03_LPM_SCSR_WDENINT_MASK) == 0U) {
        test_runtime_fail(SYS_LPM_IDLE_WATCHDOG_BASIC_FAIL_BAD_SCSR);
    }

    for (iter = 0U; iter < SYS_LPM_IDLE_WATCHDOG_BASIC_REPEAT_COUNT; ++iter) {
        Uint16 prev_count;

        prev_count = g_sys_lpm_idle_watchdog_basic_count;

        ServiceDog();
        lpm_case_program_lpmcr0(0U, 0U, S03_LPM_MODE_IDLE);
        lpm_case_watchdog_enable_div1();
        lpm_case_enter_idle();

        if (g_sys_lpm_idle_watchdog_basic_count != (Uint16)(prev_count + 1U)) {
            test_runtime_fail(SYS_LPM_IDLE_WATCHDOG_BASIC_FAIL_NO_ISR);
        }

        if (lpm_case_wait_wdint_inactive(SYS_LPM_IDLE_WATCHDOG_BASIC_WDINT_WAIT_LOOPS) != 0U) {
            test_runtime_fail(SYS_LPM_IDLE_WATCHDOG_BASIC_FAIL_WDINT_STUCK);
        }

        lpm_case_watchdog_disable();
    }

    lpm_case_disable_group1_irq();
    test_runtime_pass();
}
