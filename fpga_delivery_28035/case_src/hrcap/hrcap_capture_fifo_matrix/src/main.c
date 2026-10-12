#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "test_runtime.h"

volatile Uint16 g_hrcap_stim_stage;
volatile Uint16 g_hrcap_fifo_rise0;
volatile Uint16 g_hrcap_fifo_rise1;
volatile Uint16 g_hrcap_fifo_fall0;
volatile Uint16 g_hrcap_fifo_fall1;

void main(void)
{
    board_demo_init();
    hrcap_case_enable_clocks();
    hrcap_case_select_default_pads();
    hrcap_case_config(&HRCap1Regs, 0x0100U);
    g_hrcap_stim_stage = HRCAP_STAGE_ARMED;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL, 1000000UL))
        test_runtime_fail(0x6421U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL);
    g_hrcap_stim_stage = HRCAP_STAGE_MEASURE;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL, 1000000UL))
        test_runtime_fail(0x6422U);
    g_hrcap_fifo_rise0 = HRCap1Regs.HCCAPCNTRISE0;
    g_hrcap_fifo_rise1 = HRCap1Regs.HCCAPCNTRISE1;
    g_hrcap_fifo_fall0 = HRCap1Regs.HCCAPCNTFALL0;
    g_hrcap_fifo_fall1 = HRCap1Regs.HCCAPCNTFALL1;
    if ((g_hrcap_fifo_rise0 == 0U) || (g_hrcap_fifo_fall0 == 0U) ||
        (g_hrcap_fifo_rise1 == 0U) || (g_hrcap_fifo_fall1 == 0U))
        test_runtime_fail(0x6423U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    test_runtime_pass();
}
