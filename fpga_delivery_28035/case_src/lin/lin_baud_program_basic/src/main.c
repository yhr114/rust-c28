#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_BAUD0 0x4C5501UL
#define FAIL_BAUD1 0x4C5502UL
#define FAIL_BAUD2 0x4C5503UL

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();

    lin_case_program_baud(64U, 7U, 48U);
    if (LinaRegs.BRSR.bit.SCI_LIN_PSL != 64U || LinaRegs.BRSR.bit.M != 7U) {
        test_runtime_fail(FAIL_BAUD0 + (unsigned long)LinaRegs.BRSR.all);
    }
    if ((LinaRegs.MBRSR & 0x00FFU) != 48U) {
        test_runtime_fail(FAIL_BAUD1 + (unsigned long)LinaRegs.MBRSR);
    }

    lin_case_program_baud(96U, 11U, 92U);
    if (LinaRegs.BRSR.bit.SCI_LIN_PSL != 96U || LinaRegs.BRSR.bit.M != 11U ||
        (LinaRegs.MBRSR & 0x00FFU) != 92U) {
        test_runtime_fail(FAIL_BAUD2 + (unsigned long)LinaRegs.BRSR.all);
    }

    test_runtime_pass();
}

