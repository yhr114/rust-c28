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
    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    can_case_setup_tx_mbox_ext(CAN_CASE_TX_MBOX0,
                               CAN_EXTID_FILTER_BASIC_REJECT_ID,
                               CAN_EXTID_FILTER_BASIC_DLC,
                               CAN_EXTID_FILTER_BASIC_DATA_LO,
                               CAN_EXTID_FILTER_BASIC_DATA_HI);
    can_case_setup_rx_mbox_ext(CAN_CASE_RX_MBOX1,
                               CAN_EXTID_FILTER_BASIC_EXPECT_ID);

    can_case_send(CAN_CASE_TX_MBOX0);
    if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                               (1UL << CAN_CASE_TX_MBOX0),
                               CAN_EXTID_FILTER_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_REJ_ACK);
    }
    board_delay_us(CAN_EXTID_FILTER_BASIC_SETTLE_US);
    if ((ECanaRegs.CANRMP.all & (1UL << CAN_CASE_RX_MBOX1)) != 0UL) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_REJ_HIT);
    }

    can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);

    can_case_setup_tx_mbox_ext(CAN_CASE_TX_MBOX0,
                               CAN_EXTID_FILTER_BASIC_EXPECT_ID,
                               CAN_EXTID_FILTER_BASIC_DLC,
                               CAN_EXTID_FILTER_BASIC_DATA_LO,
                               CAN_EXTID_FILTER_BASIC_DATA_HI);
    can_case_send(CAN_CASE_TX_MBOX0);
    if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                               (1UL << CAN_CASE_TX_MBOX0),
                               CAN_EXTID_FILTER_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_MAT_ACK);
    }
    if (can_case_wait_for_mask(&ECanaRegs.CANRMP.all,
                               (1UL << CAN_CASE_RX_MBOX1),
                               CAN_EXTID_FILTER_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_MAT_RX);
    }
    if (can_case_read_rx_data_lo(CAN_CASE_RX_MBOX1) !=
        CAN_EXTID_FILTER_BASIC_DATA_LO) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_DATA_LO);
    }
    if (can_case_read_rx_data_hi(CAN_CASE_RX_MBOX1) !=
        CAN_EXTID_FILTER_BASIC_DATA_HI) {
        test_runtime_fail(CAN_EXTID_FILTER_BASIC_FAIL_DATA_HI);
    }

    can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);
    can_case_clear_rx_pending(CAN_CASE_RX_MBOX1);
    test_runtime_pass();
}
