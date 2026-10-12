#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();
    lin_case_program_format_length(3U);
    lin_case_clear_all_flags();
    board_delay_us(LIN_RX_RXCNT_BOUNDARY_WAIT_US);
    test_runtime_pass();
}
