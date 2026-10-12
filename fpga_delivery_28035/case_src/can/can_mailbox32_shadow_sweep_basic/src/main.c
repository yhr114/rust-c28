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
    unsigned int i;
    Uint32 mask;

    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    for (i = 0U; i < 32U; ++i) {
        volatile struct MBOX *mbx = can_case_mbox_ptr(i);
        volatile union CANLAM_REG *lam = can_case_lam_ptr(i);
        mask = (1UL << i);

        ECanaRegs.CANME.all &= ~mask;
        if ((i & 1U) != 0U) {
            ECanaRegs.CANMD.all |= mask;
            mbx->MSGID.all = CAN_CASE_EXT_ID(0x10000UL + (Uint32)i);
            lam->all = 0x1FFFFFFFUL ^ ((Uint32)i << 3);
        } else {
            ECanaRegs.CANMD.all &= ~mask;
            mbx->MSGID.all = CAN_CASE_STD_ID(0x200UL + (Uint32)i);
            lam->all = ((Uint32)i << 18);
        }
        mbx->MSGCTRL.all = 0U;
        mbx->MSGCTRL.bit.DLC = (Uint16)(i & 0x7U);
        mbx->MDL.all = 0x11110000UL ^ ((Uint32)i * 0x01010101UL);
        mbx->MDH.all = 0xAAAA0000UL ^ ((Uint32)i * 0x00110011UL);
        ECanaRegs.CANRMP.all = mask;
        ECanaRegs.CANTA.all = mask;
        ECanaRegs.CANME.all |= mask;

        if (mbx->MDL.all != (0x11110000UL ^ ((Uint32)i * 0x01010101UL))) {
            test_runtime_fail(CAN_MAILBOX32_SHADOW_SWEEP_BASIC_FAIL_MBOX + i);
        }
    }

    /* This case targets mailbox[0:31] shadow/config programming coverage.
     * Leave transport success/ACK checking to dedicated tx/self-test cases. */
    test_runtime_pass();
}
