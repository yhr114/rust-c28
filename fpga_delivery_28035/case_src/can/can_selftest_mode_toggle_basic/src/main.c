#include "board_can_case.h"
#include "case_config.h"
#include "test_runtime.h"

static void can_case_set_stm_dbo(unsigned int self_test_enable, unsigned int dbo_enable)
{
    struct ECAN_REGS shadow;

    EALLOW;
    can_case_enter_config();
    shadow.CANMC.all = ECanaRegs.CANMC.all;
    shadow.CANMC.bit.STM = (self_test_enable != 0U) ? 1U : 0U;
    shadow.CANMC.bit.DBO = (dbo_enable != 0U) ? 1U : 0U;
    ECanaRegs.CANMC.all = shadow.CANMC.all;
    can_case_leave_config();
    EDIS;
}

void main(void)
{
    board_demo_init();
    can_case_basic_init(0U);

    if ((unsigned int)ECanaRegs.CANMC.bit.STM != 0U) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_STM0);
    }

    can_case_set_stm_dbo(1U, 1U);

    if ((unsigned int)ECanaRegs.CANMC.bit.STM == 0U) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_STM1);
    }

    can_case_setup_tx_mbox(CAN_CASE_TX_MBOX0,
                           CAN_SELFTEST_MODE_TOGGLE_BASIC_STD_ID,
                           CAN_SELFTEST_MODE_TOGGLE_BASIC_DLC,
                           CAN_SELFTEST_MODE_TOGGLE_BASIC_DATA_LO,
                           CAN_SELFTEST_MODE_TOGGLE_BASIC_DATA_HI);
    can_case_setup_rx_mbox(CAN_CASE_RX_MBOX1,
                           CAN_SELFTEST_MODE_TOGGLE_BASIC_STD_ID);

    can_case_send(CAN_CASE_TX_MBOX0);

    if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                               (1UL << CAN_CASE_TX_MBOX0),
                               CAN_SELFTEST_MODE_TOGGLE_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_TX_ACK);
    }
    if (can_case_wait_for_mask(&ECanaRegs.CANRMP.all,
                               (1UL << CAN_CASE_RX_MBOX1),
                               CAN_SELFTEST_MODE_TOGGLE_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_RX_PEND);
    }
    if (can_case_read_rx_data_lo(CAN_CASE_RX_MBOX1) !=
        CAN_SELFTEST_MODE_TOGGLE_BASIC_DATA_LO) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_DATA_LO);
    }
    if (can_case_read_rx_data_hi(CAN_CASE_RX_MBOX1) !=
        CAN_SELFTEST_MODE_TOGGLE_BASIC_DATA_HI) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_DATA_HI);
    }

    can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);
    can_case_clear_rx_pending(CAN_CASE_RX_MBOX1);
    can_case_set_stm_dbo(0U, 1U);

    if ((unsigned int)ECanaRegs.CANMC.bit.STM != 0U) {
        test_runtime_fail(CAN_SELFTEST_MODE_TOGGLE_BASIC_FAIL_STM_CLR);
    }

    test_runtime_pass();
}
