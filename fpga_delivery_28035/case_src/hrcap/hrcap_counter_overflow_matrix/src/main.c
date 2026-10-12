#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "test_runtime.h"

volatile Uint16 g_hrcap_stim_stage;
volatile Uint16 g_hrcap_counterovf_flags;
volatile Uint16 g_hrcap_counter_after_clear;

void main(void)
{
    board_demo_init();
    hrcap_case_enable_clocks();
    hrcap_case_select_default_pads();
    hrcap_case_config(&HRCap1Regs, 0x0108U);
    g_hrcap_stim_stage = HRCAP_STAGE_OVERFLOW;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_COUNTEROVF, 0x0FFFFFFFUL))
        test_runtime_fail(0x6451U);
    g_hrcap_counterovf_flags = HRCap1Regs.HCIFR.all;
    if ((g_hrcap_counterovf_flags & HRCAP_CASE_FLAG_INT) == 0U)
        test_runtime_fail(0x6452U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_COUNTEROVF | HRCAP_CASE_FLAG_INT);
    if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_COUNTEROVF, 10000UL))
        test_runtime_fail(0x6453U);
    g_hrcap_counter_after_clear = HRCap1Regs.HCCOUNTER;
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    test_runtime_pass();
}
