#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "test_runtime.h"

volatile Uint16 g_hrcap_stim_stage;
volatile Uint16 g_hrcap_int_disabled_flags;
volatile Uint16 g_hrcap_int_enabled_flags;

void main(void)
{
    board_demo_init();
    hrcap_case_enable_clocks();
    hrcap_case_select_default_pads();
    hrcap_case_config(&HRCap1Regs, 0x0100U);
    g_hrcap_stim_stage = HRCAP_STAGE_ARMED;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL, 1000000UL))
        test_runtime_fail(0x6431U);
    g_hrcap_int_disabled_flags = HRCap1Regs.HCIFR.all;
    if ((g_hrcap_int_disabled_flags & HRCAP_CASE_FLAG_INT) != 0U)
        test_runtime_fail(0x6432U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    hrcap_case_config(&HRCap1Regs, 0x010EU);
    g_hrcap_stim_stage = HRCAP_STAGE_MEASURE;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_RISE | HRCAP_CASE_FLAG_FALL, 1000000UL))
        test_runtime_fail(0x6433U);
    g_hrcap_int_enabled_flags = HRCap1Regs.HCIFR.all;
    if ((g_hrcap_int_enabled_flags & HRCAP_CASE_FLAG_INT) == 0U)
        test_runtime_fail(0x6434U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_RISE);
    if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_RISE, 10000UL))
        test_runtime_fail(0x6435U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    if (!hrcap_case_wait_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL, 10000UL))
        test_runtime_fail(0x6436U);
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    test_runtime_pass();
}
