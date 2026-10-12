#include "board_can_case.h"
#include "case_config.h"
#include "test_runtime.h"

static void can_case_enable_selftest_dbo(void)
{
    struct ECAN_REGS shadow;

    EALLOW;
    can_case_enter_config();
    shadow.CANMC.all = ECanaRegs.CANMC.all;
    shadow.CANMC.bit.STM = 1U;
    shadow.CANMC.bit.DBO = 1U;
    ECanaRegs.CANMC.all = shadow.CANMC.all;
    can_case_leave_config();
    EDIS;
}

void main(void)
{
    Uint32 tx_mask = (Uint32)(1UL << CAN_CASE_TX_MBOX0);
    Uint32 rx_mask = (Uint32)(1UL << CAN_CASE_RX_MBOX1);

    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    can_case_setup_tx_mbox(CAN_CASE_TX_MBOX0,
                           CAN_STATUS_FLAG_CLEAR_BASIC_STD_ID,
                           CAN_STATUS_FLAG_CLEAR_BASIC_DLC,
                           CAN_STATUS_FLAG_CLEAR_BASIC_DATA_LO,
                           CAN_STATUS_FLAG_CLEAR_BASIC_DATA_HI);
    can_case_setup_rx_mbox(CAN_CASE_RX_MBOX1,
                           CAN_STATUS_FLAG_CLEAR_BASIC_STD_ID);

    can_case_send(CAN_CASE_TX_MBOX0);

    if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                               tx_mask,
                               CAN_STATUS_FLAG_CLEAR_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_STATUS_FLAG_CLEAR_BASIC_FAIL_TX_ACK);
    }
    if (can_case_wait_for_mask(&ECanaRegs.CANRMP.all,
                               rx_mask,
                               CAN_STATUS_FLAG_CLEAR_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_STATUS_FLAG_CLEAR_BASIC_FAIL_RX_PEND);
    }

    can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);
    can_case_clear_rx_pending(CAN_CASE_RX_MBOX1);

    if ((ECanaRegs.CANTA.all & tx_mask) != 0UL) {
        test_runtime_fail(CAN_STATUS_FLAG_CLEAR_BASIC_FAIL_TX_CLEAR);
    }
    if ((ECanaRegs.CANRMP.all & rx_mask) != 0UL) {
        test_runtime_fail(CAN_STATUS_FLAG_CLEAR_BASIC_FAIL_RX_CLEAR);
    }

    ECanaRegs.CANGIF0.all = 0xFFFFFFFFUL;
    ECanaRegs.CANGIF1.all = 0xFFFFFFFFUL;
    test_runtime_pass();
}
