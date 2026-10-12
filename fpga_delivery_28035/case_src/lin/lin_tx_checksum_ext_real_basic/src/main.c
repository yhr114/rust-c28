#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_GCR1 0x4D2501UL
#define FAIL_TD0  0x4D2502UL
#define FAIL_TD1  0x4D2503UL

void main(void)
{
    unsigned long rd;
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();
    lin_case_set_soft_reset(0U);
    EALLOW;
    LinaRegs.SCIGCR1.bit.CLK_MASTER = 0U;
    LinaRegs.SCIGCR1.bit.HGENCTRL = 0U;
    LinaRegs.SCIGCR1.bit.MBUFMODE = 1U;
    LinaRegs.SCIGCR1.bit.CTYPE = 1U;
    LinaRegs.SCIGCR1.bit.RXENA = 1U;
    LinaRegs.SCIGCR1.bit.TXENA = 1U;
    LinaRegs.SCIGCR2.bit.SC = 1U;
    EDIS;
    lin_case_program_format_length(7U);
    lin_case_program_masks(0x3FU, 0x3FU);
    lin_case_set_id_register(0x10U, 0x10U);
    lin_case_write_td0(LIN_TX_CHECKSUM_TD0);
    lin_case_write_td1(LIN_TX_CHECKSUM_TD1);
    lin_case_clear_all_flags();
    lin_case_set_soft_reset(1U);
    if (LinaRegs.SCIGCR1.bit.LINMODE != 1U || LinaRegs.SCIGCR1.bit.MBUFMODE != 1U || LinaRegs.SCIGCR2.bit.SC != 1U) {
        test_runtime_fail(FAIL_GCR1 + (unsigned long)LinaRegs.SCIGCR1.all);
    }
    rd = lin_case_reg_read32(LIN_REGIDX_TD0);
    if (rd != LIN_TX_CHECKSUM_TD0) {
        test_runtime_fail(FAIL_TD0 + rd);
    }
    rd = lin_case_reg_read32(LIN_REGIDX_TD1);
    if (rd != LIN_TX_CHECKSUM_TD1) {
        test_runtime_fail(FAIL_TD1 + rd);
    }
    board_delay_us(LIN_TX_CHECKSUM_WAIT_US);
    test_runtime_pass();
}
