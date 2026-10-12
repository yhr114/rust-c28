#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();
    lin_case_set_soft_reset(0U);
    EALLOW;
    LinaRegs.SCIGCR1.bit.LINMODE = 0U;
    LinaRegs.SCIGCR1.bit.MBUFMODE = 1U;
    LinaRegs.SCIGCR1.bit.RXENA = 1U;
    LinaRegs.SCIGCR1.bit.TXENA = 0U;
    EDIS;
    lin_case_program_format_length(7U);
    lin_case_clear_all_flags();
    lin_case_set_soft_reset(1U);
    board_delay_us(LIN_SCI_MULTIBUF_RDSLOT_WAIT_US);
    (void)lin_case_reg_read32(LIN_REGIDX_RD0);
    (void)lin_case_reg_read32(LIN_REGIDX_RD1);
    test_runtime_pass();
}
