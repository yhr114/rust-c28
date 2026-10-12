#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for pie_mask_ack_basic
#endif

static volatile unsigned int g_pie_mask_ack_basic_seen = 0U;

__interrupt void pie_mask_ack_basic_timer0_isr(void)
{
    g_pie_mask_ack_basic_seen++;
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}

static unsigned int wait_for_irq_count(unsigned int expected_count, unsigned int fail_code)
{
    unsigned long loops;

    for (loops = 0UL; loops < PIE_MASK_ACK_BASIC_WAIT_LOOPS; ++loops) {
        if (g_pie_mask_ack_basic_seen >= expected_count) {
            return 0U;
        }
    }

    return fail_code;
}

static unsigned int wait_for_irq_stable(unsigned int snapshot)
{
    unsigned long loops;

    for (loops = 0UL; loops < PIE_MASK_ACK_BASIC_MASK_WINDOW_LOOPS; ++loops) {
        if (g_pie_mask_ack_basic_seen != snapshot) {
            return PIE_MASK_ACK_BASIC_FAIL_MASK_LEAK;
        }
    }

    return 0U;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();

    EALLOW;
    PieVectTable.TINT0 = &pie_mask_ack_basic_timer0_isr;
    EDIS;

    InitCpuTimers();
    ConfigCpuTimer(&CpuTimer0, 60.0F, (float)PIE_MASK_ACK_BASIC_TIMER_US);

    PieCtrlRegs.PIECTRL.bit.ENPIE = 1;
    PieCtrlRegs.PIEIER1.bit.INTx7 = 1;
    IER |= M_INT1;

    EINT;
    ERTM;

    CpuTimer0Regs.TCR.all = 0x4000;

    fail_code = wait_for_irq_count(1U, PIE_MASK_ACK_BASIC_FAIL_FIRST_IRQ);

    if (fail_code == 0U) {
        PieCtrlRegs.PIEIER1.bit.INTx7 = 0;
        fail_code = wait_for_irq_stable(1U);
    }

    if (fail_code == 0U) {
        PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
        PieCtrlRegs.PIEIER1.bit.INTx7 = 1;
        fail_code = wait_for_irq_count(2U, PIE_MASK_ACK_BASIC_FAIL_REENABLE);
    }

    CpuTimer0Regs.TCR.bit.TSS = 1;
    DINT;

    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    board_demo_toggle();
    test_runtime_pass();
}
