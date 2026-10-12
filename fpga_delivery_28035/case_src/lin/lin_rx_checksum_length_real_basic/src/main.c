#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_FMT 0x4D2301UL
#define FAIL_FLR 0x4D2302UL
#define LIN_FATAL_ERR_MASK (LIN_FLR_PE_MASK | LIN_FLR_OE_MASK | LIN_FLR_FE_MASK | LIN_FLR_ISFE_MASK | LIN_FLR_PBE_MASK | LIN_FLR_BE_MASK)

void main(void)
{
    unsigned long rd;
    unsigned int len;
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
    LinaRegs.SCIGCR1.bit.TXENA = 0U;
    LinaRegs.SCIGCR2.bit.CC = 1U;
    EDIS;
    lin_case_program_masks(0x3FU, 0x3FU);
    lin_case_set_id_register(0x10U, 0x10U);
    lin_case_clear_all_flags();
    lin_case_set_soft_reset(1U);
    for (len = 0U; len < 4U; len++) {
        lin_case_program_format_length(len);
        rd = lin_case_reg_read32(LIN_REGIDX_FORMAT);
        if (((rd >> 16) & 0x7UL) != (unsigned long)len) {
            test_runtime_fail(FAIL_FMT + rd + len);
        }
        board_delay_us(LIN_RX_CHECKSUM_LENGTH_STEP_WAIT_US);
    }
    rd = lin_case_reg_read32(LIN_REGIDX_FLR);
    (void)rd;
    test_runtime_pass();
}
