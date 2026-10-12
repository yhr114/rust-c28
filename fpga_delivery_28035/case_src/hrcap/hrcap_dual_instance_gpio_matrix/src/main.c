#include "board_gpio.h"
#include "board_hrcap_case.h"
#include "test_runtime.h"

volatile Uint16 g_hrcap_stim_stage;
volatile Uint16 g_hrcap_dual_flags1;
volatile Uint16 g_hrcap_dual_flags2;

void main(void)
{
    board_demo_init();
    hrcap_case_enable_clocks();
    hrcap_case_select_default_pads();
    hrcap_case_config(&HRCap1Regs, 0x0102U);
    hrcap_case_config(&HRCap2Regs, 0x0102U);
    if ((GpioCtrlRegs.GPAMUX2.bit.GPIO26 != 1U) ||
        (GpioCtrlRegs.GPAMUX2.bit.GPIO27 != 1U))
        test_runtime_fail(0x6481U);
    g_hrcap_stim_stage = HRCAP_STAGE_ARMED;
    if (!hrcap_case_wait_set(&HRCap1Regs, HRCAP_CASE_FLAG_RISE, 1000000UL))
        test_runtime_fail(0x6482U);
    g_hrcap_dual_flags1 = HRCap1Regs.HCIFR.all;
    g_hrcap_dual_flags2 = HRCap2Regs.HCIFR.all;
    if ((g_hrcap_dual_flags2 & HRCAP_CASE_FLAG_RISE) != 0U)
        test_runtime_fail(0x6483U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    hrcap_case_clear(&HRCap2Regs, HRCAP_CASE_FLAG_ALL);
    g_hrcap_stim_stage = HRCAP_STAGE_MEASURE;
    if (!hrcap_case_wait_set(&HRCap2Regs, HRCAP_CASE_FLAG_RISE, 1000000UL))
        test_runtime_fail(0x6484U);
    g_hrcap_dual_flags1 = HRCap1Regs.HCIFR.all;
    g_hrcap_dual_flags2 = HRCap2Regs.HCIFR.all;
    if ((g_hrcap_dual_flags1 & HRCAP_CASE_FLAG_RISE) != 0U)
        test_runtime_fail(0x6485U);
    hrcap_case_clear(&HRCap1Regs, HRCAP_CASE_FLAG_ALL);
    hrcap_case_clear(&HRCap2Regs, HRCAP_CASE_FLAG_ALL);
    g_hrcap_stim_stage = HRCAP_STAGE_FINISH;
    test_runtime_pass();
}
