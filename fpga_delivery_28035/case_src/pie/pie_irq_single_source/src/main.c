#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device for pie_irq_single_source
#endif

static volatile unsigned int g_pie_irq_single_source_seen = 0U;

__interrupt void pie_irq_single_source_timer0_isr(void)
{
    g_pie_irq_single_source_seen++;
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}

static unsigned int wait_for_timer0_irq(void)
{
    unsigned long loops;

    for (loops = 0UL; loops < PIE_IRQ_SINGLE_SOURCE_WAIT_LOOPS; ++loops) {
        if (g_pie_irq_single_source_seen != 0U) {
            return 0U;
        }
    }

    return PIE_IRQ_SINGLE_SOURCE_FAIL_TIMEOUT;
}

void main(void)
{
    unsigned int fail_code;

    board_demo_init();

    EALLOW;
    PieVectTable.TINT0 = &pie_irq_single_source_timer0_isr;
    EDIS;

    InitCpuTimers();
    ConfigCpuTimer(&CpuTimer0, 60.0F, (float)PIE_IRQ_SINGLE_SOURCE_TIMER_US);

    PieCtrlRegs.PIECTRL.bit.ENPIE = 1;
    PieCtrlRegs.PIEIER1.bit.INTx7 = 1;
    IER |= M_INT1;

    EINT;
    ERTM;

    CpuTimer0Regs.TCR.all = 0x4000;

    fail_code = wait_for_timer0_irq();

    CpuTimer0Regs.TCR.bit.TSS = 1;
    DINT;

    if (fail_code != 0U) {
        test_runtime_fail(fail_code);
    }

    board_demo_toggle();
    test_runtime_pass();
}
