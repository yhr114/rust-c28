#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_WAKE_INT  0x4C7A01UL
#define FAIL_WAKE_LVL  0x4C7A02UL
#define FAIL_WAKE_CLR  0x4C7A03UL
#define FAIL_WAKE_FLR  0x4C7A04UL
#define FAIL_BRK_MODE  0x4C7A05UL
#define FAIL_BRK_INT   0x4C7A06UL
#define FAIL_BRK_LVL   0x4C7A07UL
#define FAIL_BRK_CLR   0x4C7A08UL
#define FAIL_BRK_FLR   0x4C7A09UL

void main(void)
{
    unsigned long rd;

    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();

    lin_case_set_interrupt_bits(LIN_INT_WAKEUP_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINT);
    if ((rd & LIN_INT_WAKEUP_MASK) != LIN_INT_WAKEUP_MASK) {
        test_runtime_fail(FAIL_WAKE_INT + rd);
    }

    lin_case_set_interrupt_level_bits(LIN_INT_WAKEUP_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINTLVL);
    if ((rd & LIN_INT_WAKEUP_MASK) != LIN_INT_WAKEUP_MASK) {
        test_runtime_fail(FAIL_WAKE_LVL + rd);
    }

    lin_case_clear_flr_bits(LIN_FLR_WAKEUP_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_FLR);
    if ((rd & LIN_FLR_WAKEUP_MASK) != 0UL) {
        test_runtime_fail(FAIL_WAKE_FLR + rd);
    }

    lin_case_clear_interrupt_bits(LIN_INT_WAKEUP_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINT);
    if ((rd & LIN_INT_WAKEUP_MASK) != 0UL) {
        test_runtime_fail(FAIL_WAKE_CLR + rd);
    }

    lin_case_set_lin_mode(0U);
    if (LinaRegs.SCIGCR1.bit.LINMODE != 0U) {
        test_runtime_fail(FAIL_BRK_MODE + (unsigned long)LinaRegs.SCIGCR1.all);
    }

    lin_case_set_interrupt_bits(LIN_INT_BRKDT_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINT);
    if ((rd & LIN_INT_BRKDT_MASK) != LIN_INT_BRKDT_MASK) {
        test_runtime_fail(FAIL_BRK_INT + rd);
    }

    lin_case_set_interrupt_level_bits(LIN_INT_BRKDT_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINTLVL);
    if ((rd & LIN_INT_BRKDT_MASK) != LIN_INT_BRKDT_MASK) {
        test_runtime_fail(FAIL_BRK_LVL + rd);
    }

    lin_case_clear_flr_bits(LIN_FLR_BRKDT_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_FLR);
    if ((rd & LIN_FLR_BRKDT_MASK) != 0UL) {
        test_runtime_fail(FAIL_BRK_FLR + rd);
    }

    lin_case_clear_interrupt_bits(LIN_INT_BRKDT_MASK);
    rd = lin_case_reg_read32(LIN_REGIDX_SETINT);
    if ((rd & LIN_INT_BRKDT_MASK) != 0UL) {
        test_runtime_fail(FAIL_BRK_CLR + rd);
    }

    test_runtime_pass();
}
