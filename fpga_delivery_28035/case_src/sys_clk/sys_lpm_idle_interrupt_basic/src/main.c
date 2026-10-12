#include "board_lpm_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#else
#error Unsupported device for sys_lpm_idle_interrupt_basic
#endif

volatile Uint16 g_sys_lpm_idle_interrupt_basic_count = 0U;
volatile Uint16 g_sys_lpm_idle_interrupt_basic_resume = 0U;

__interrupt void sys_lpm_idle_interrupt_basic_isr(void)
{
    g_sys_lpm_idle_interrupt_basic_count++;
    lpm_case_timer0_stop();
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}

void main(void)
{
    Uint16 iter;

    board_demo_init();
    DisableDog();

    EALLOW;
    PieVectTable.TINT0 = &sys_lpm_idle_interrupt_basic_isr;
    EDIS;

    lpm_case_enable_tint0_irq();

    for (iter = 0U; iter < SYS_LPM_IDLE_INTERRUPT_BASIC_REPEAT_COUNT; ++iter) {
        Uint16 prev_count;
        Uint16 prev_resume;

        prev_count = g_sys_lpm_idle_interrupt_basic_count;
        prev_resume = g_sys_lpm_idle_interrupt_basic_resume;

        lpm_case_timer0_start_us(SYS_LPM_IDLE_INTERRUPT_BASIC_TIMER_US);
        lpm_case_program_lpmcr0(0U, 0U, S03_LPM_MODE_IDLE);
        lpm_case_enter_idle();
        g_sys_lpm_idle_interrupt_basic_resume++;

        if (g_sys_lpm_idle_interrupt_basic_count != (Uint16)(prev_count + 1U)) {
            test_runtime_fail(SYS_LPM_IDLE_INTERRUPT_BASIC_FAIL_NO_ISR);
        }

        if (g_sys_lpm_idle_interrupt_basic_resume != (Uint16)(prev_resume + 1U)) {
            test_runtime_fail(SYS_LPM_IDLE_INTERRUPT_BASIC_FAIL_NO_RESUME);
        }
    }

    lpm_case_disable_group1_irq();
    test_runtime_pass();
}
