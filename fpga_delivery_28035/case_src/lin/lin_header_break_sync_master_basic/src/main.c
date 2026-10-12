#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_COMP 0x4C6201UL
#define FAIL_ID   0x4C6202UL

void main(void)
{
    unsigned long rd;

    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_master_cfg_only();
    lin_case_program_compare(7U, 2U);
    lin_case_set_id_register(0x22U, 0x35U);

    rd = lin_case_reg_read32(LIN_REGIDX_COMP);
    if ((rd & 0x00000307UL) != 0x00000207UL) {
        test_runtime_fail(FAIL_COMP + rd);
    }

    rd = lin_case_reg_read32(LIN_REGIDX_ID);
    if ((rd & 0x0000FFFFUL) != 0x00002235UL) {
        test_runtime_fail(FAIL_ID + rd);
    }

    test_runtime_pass();
}

