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
    Uint32 dlc;
    Uint32 ext_id;

    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    for (dlc = 1UL; dlc <= 7UL; ++dlc) {
        ext_id = CAN_RX_EXTID_DLC_SWEEP_BASIC_BASE_ID + dlc;

        can_case_setup_tx_mbox_ext(CAN_CASE_TX_MBOX0,
                                   ext_id,
                                   dlc,
                                   CAN_RX_EXTID_DLC_SWEEP_BASIC_DATA_LO + dlc,
                                   CAN_RX_EXTID_DLC_SWEEP_BASIC_DATA_HI + dlc);
        can_case_setup_rx_mbox_ext(CAN_CASE_RX_MBOX1, ext_id);

        can_case_send(CAN_CASE_TX_MBOX0);

        if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                                   (1UL << CAN_CASE_TX_MBOX0),
                                   CAN_RX_EXTID_DLC_SWEEP_BASIC_WAIT_LOOPS) != 0U) {
            test_runtime_fail(CAN_RX_EXTID_DLC_SWEEP_BASIC_FAIL_TX_ACK + (Uint16)dlc);
        }
        if (can_case_wait_for_mask(&ECanaRegs.CANRMP.all,
                                   (1UL << CAN_CASE_RX_MBOX1),
                                   CAN_RX_EXTID_DLC_SWEEP_BASIC_WAIT_LOOPS) != 0U) {
            test_runtime_fail(CAN_RX_EXTID_DLC_SWEEP_BASIC_FAIL_RX_PEND + (Uint16)dlc);
        }
        if ((Uint32)can_case_mbox_ptr(CAN_CASE_RX_MBOX1)->MSGCTRL.bit.DLC != dlc) {
            test_runtime_fail(CAN_RX_EXTID_DLC_SWEEP_BASIC_FAIL_RX_DLC + (Uint16)dlc);
        }
        if ((can_case_mbox_ptr(CAN_CASE_RX_MBOX1)->MSGID.all & (1UL << 31)) == 0UL) {
            test_runtime_fail(CAN_RX_EXTID_DLC_SWEEP_BASIC_FAIL_RX_IDE + (Uint16)dlc);
        }

        can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);
        can_case_clear_rx_pending(CAN_CASE_RX_MBOX1);
    }

    test_runtime_pass();
}
