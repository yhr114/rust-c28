#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_DFT0 0x4C5A01UL
#define FAIL_DFT1 0x4C5A02UL

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();

    lin_case_set_iodft_loopback(1U);
    if (LinaRegs.IODFTCTRL.bit.IODFTENA != 1U || LinaRegs.IODFTCTRL.bit.LPBENA != 1U) {
        test_runtime_fail(FAIL_DFT0 + (unsigned long)LinaRegs.IODFTCTRL.all);
    }

    lin_case_set_iodft_loopback(0U);
    if (LinaRegs.IODFTCTRL.bit.IODFTENA != 0U || LinaRegs.IODFTCTRL.bit.LPBENA != 0U) {
        test_runtime_fail(FAIL_DFT1 + (unsigned long)LinaRegs.IODFTCTRL.all);
    }

    test_runtime_pass();
}

