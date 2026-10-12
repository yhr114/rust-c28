#include "board_can_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define CAN_CASE_MSGID_AME (1UL << 30)

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

static void can_case_setup_masked_rx_mbox1(void)
{
    Uint32 mask = (1UL << CAN_CASE_RX_MBOX1);
    volatile struct MBOX *mbx = can_case_mbox_ptr(CAN_CASE_RX_MBOX1);

    can_case_setup_rx_mbox(CAN_CASE_RX_MBOX1,
                           CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_RX_ID);

    ECanaRegs.CANME.all &= ~mask;
    mbx->MSGID.all =
        CAN_CASE_STD_ID(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_RX_ID) |
        CAN_CASE_MSGID_AME;
    can_case_lam_ptr(CAN_CASE_RX_MBOX1)->all =
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_LAM1_MASK;
    ECanaRegs.CANRMP.all = mask;
    ECanaRegs.CANME.all |= mask;
}

void main(void)
{
    Uint32 rx_mask = (1UL << CAN_CASE_RX_MBOX1);

    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    ECanaRegs.CANGAM.all = CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_GAM_PATTERN;
    if ((ECanaRegs.CANGAM.all & 0x1FFFFFFFUL) !=
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_GAM_PATTERN) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_GAM);
    }
    ECanaRegs.CANGAM.all = 0U;

    ECanaRegs.CANOPC.all = CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_OPC_PATTERN;
    if ((ECanaRegs.CANOPC.all & CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_OPC_PATTERN) !=
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_OPC_PATTERN) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_OPC);
    }

    can_case_setup_tx_mbox(CAN_CASE_TX_MBOX0,
                           CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_TX_ID,
                           CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_DLC,
                           CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_DATA_LO,
                           CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_DATA_HI);
    can_case_setup_masked_rx_mbox1();

    if (can_case_lam_ptr(CAN_CASE_RX_MBOX1)->all !=
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_LAM1_MASK) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_LAM1);
    }

    can_case_send(CAN_CASE_TX_MBOX0);
    if (can_case_wait_for_mask(&ECanaRegs.CANTA.all,
                               (1UL << CAN_CASE_TX_MBOX0),
                               CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_HIT_ACK);
    }
    if (can_case_wait_for_mask(&ECanaRegs.CANRMP.all,
                               rx_mask,
                               CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_WAIT_LOOPS) != 0U) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_HIT_RX);
    }
    if (can_case_read_rx_data_lo(CAN_CASE_RX_MBOX1) !=
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_DATA_LO) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_DATA_LO);
    }
    if (can_case_read_rx_data_hi(CAN_CASE_RX_MBOX1) !=
        CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_DATA_HI) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_DATA_HI);
    }
    if ((unsigned int)ECanaRegs.CANES.bit.ACKE != 0U) {
        test_runtime_fail(CAN_GLOBAL_MASK_OPCODE_SHADOW_BASIC_FAIL_ACKE);
    }

    can_case_clear_tx_ack(CAN_CASE_TX_MBOX0);
    can_case_clear_rx_pending(CAN_CASE_RX_MBOX1);
    test_runtime_pass();
}
