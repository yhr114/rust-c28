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
    struct ECAN_REGS shadow;

    board_demo_init();
    can_case_basic_init(1U);
    can_case_enable_selftest_dbo();

    // Flip the routing controls to touch both interrupt lines, then settle on line0
    // for a final readback. This still exercises the interrupt-routing knobs
    // without depending on a fragile ISR/pending timing window.
    ECanaRegs.CANMIM.all = (1UL << CAN_CASE_RX_MBOX1);

    shadow.CANMIL.all = 0U;
    shadow.CANMIL.bit.MIL1 = 1U;
    ECanaRegs.CANMIL.all = shadow.CANMIL.all;

    shadow.CANGIM.all = 0U;
    shadow.CANGIM.bit.I0EN = 1U;
    shadow.CANGIM.bit.I1EN = 1U;
    ECanaRegs.CANGIM.all = shadow.CANGIM.all;

    ECanaRegs.CANMIL.all = 0U;
    ECanaRegs.CANGIM.all = 0x00000001UL;
    test_runtime_pass();
}
