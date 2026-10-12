#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for pie_irq_ack_holdoff_release_basic
#endif

static volatile unsigned int g_pie_ack_seen = 0U;
static volatile Uint16 g_pie_ack_snapshot = 0U;
static volatile Uint16 g_pie_ack_after_release = 0U;

__interrupt void pie_irq_ack_holdoff_timer0_isr(void)
{
    g_pie_ack_seen++;
    g_pie_ack_snapshot = (Uint16)(PieCtrlRegs.PIEACK.all & PIEACK_GROUP1);

    /* Intentionally leave PIEACK set. Main verifies software W1C release. */
}

static unsigned int wait_for_first_irq(void)
{
    unsigned long loops;

    for (loops = 0UL; loops < PIE_IRQ_ACK_WAIT_LOOPS; ++loops) {
        if (g_pie_ack_seen != 0U) {
            return 0U;
        }
    }

    return PIE_IRQ_ACK_FAIL_FIRST_IRQ;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();

    EALLOW;
    PieVectTable.TINT0 = &pie_irq_ack_holdoff_timer0_isr;
    EDIS;

    InitCpuTimers();
    ConfigCpuTimer(&CpuTimer0, 60.0F, (float)PIE_IRQ_ACK_TIMER_US);

    PieCtrlRegs.PIECTRL.bit.ENPIE = 1U;
    PieCtrlRegs.PIEIER1.bit.INTx7 = 1U;
    IER |= M_INT1;

    EINT;
    ERTM;

    CpuTimer0Regs.TCR.all = 0x4000;
    fail_code = wait_for_first_irq();

    CpuTimer0Regs.TCR.bit.TSS = 1U;
    DINT;

    if ((fail_code == 0U) && (g_pie_ack_snapshot == 0U)) {
        fail_code = PIE_IRQ_ACK_FAIL_ACK_NOT_SET;
    }

    if (fail_code == 0U) {
        PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
        g_pie_ack_after_release = (Uint16)(PieCtrlRegs.PIEACK.all & PIEACK_GROUP1);
        if (g_pie_ack_after_release != 0U) {
            fail_code = PIE_IRQ_ACK_FAIL_RELEASE_STUCK;
        }
    }

    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    board_demo_toggle();
    test_runtime_pass();
}
