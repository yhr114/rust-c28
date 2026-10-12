#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_GCR1 0x4D0601UL
#define FAIL_IODFT 0x4D0602UL

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();

    lin_case_set_soft_reset(0U);
    EALLOW;
    LinaRegs.SCIGCR1.bit.LOOPBACK = 1U;
    LinaRegs.SCIGCR1.bit.ADAPT = 1U;
    LinaRegs.SCIGCR1.bit.COMMMODE = 1U;
    LinaRegs.SCIGCR1.bit.CONT = 0U;
    LinaRegs.SCIGCR1.bit.CTYPE = 1U;
    LinaRegs.SCIGCR1.bit.HGENCTRL = 1U;
    EDIS;
    lin_case_write_gcr2(LIN_GCR2_POWERDOWN_MASK | LIN_GCR2_CC_MASK);
    lin_case_set_iodft_loopback(1U);
    lin_case_set_soft_reset(1U);

    if (LinaRegs.SCIGCR1.bit.LOOPBACK != 1U ||
        LinaRegs.SCIGCR1.bit.ADAPT != 1U ||
        LinaRegs.SCIGCR1.bit.COMMMODE != 1U ||
        LinaRegs.SCIGCR1.bit.HGENCTRL != 1U) {
        test_runtime_fail(FAIL_GCR1 + (unsigned long)LinaRegs.SCIGCR1.all);
    }

    if (LinaRegs.IODFTCTRL.bit.IODFTENA != 1U ||
        LinaRegs.IODFTCTRL.bit.LPBENA != 1U) {
        test_runtime_fail(FAIL_IODFT + (unsigned long)LinaRegs.IODFTCTRL.all);
    }

    board_delay_us(LIN_TOP_MODE_LOOPBACK_POWER_CROSS_WAIT_US);
    test_runtime_pass();
}
