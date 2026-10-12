#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()

static volatile Uint16 isr_count;

static void init_eqep1_gpio(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

__interrupt void eqep1_gate_isr(void)
{
    isr_count++;
    PieCtrlRegs.PIEACK.all = PIEACK_GROUP5;
}

static Uint16 wait_for_isr_count(Uint16 expected_count)
{
    Uint32 timeout = EQEP_INT_GATE_POLL_COUNT;

    while (timeout > 0UL) {
        if (isr_count >= expected_count) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

void main(void)
{
    Uint16 first_fail_code = 0U;

    InitSysCtrl();
    init_eqep1_gpio();
    DINT;
    InitPieCtrl();
    IER = 0x0000U;
    IFR = 0x0000U;
    InitPieVectTable();

    EALLOW;
    PieVectTable.EQEP1_INT = &eqep1_gate_isr;
    EDIS;

    EQep1Regs.QEPCTL.all = 0x0000U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QPOSINIT = EQEP_INT_GATE_STAGE_INITIAL;
    EQep1Regs.QEINT.all = 0x0000U;
    EQep1Regs.QCLR.all = 0x0FFFU;

    isr_count = 0U;
    PieCtrlRegs.PIEIER5.bit.INTx1 = 1U;
    IER |= M_INT5;
    EINT;

    EQep1Regs.QEINT.bit.PCE = 1U;
    EQep1Regs.QFRC.bit.PCE = 1U;

    if (wait_for_isr_count(1U) == 0U) {
        first_fail_code = EQEP_INT_GATE_FAIL_FIRST_ISR;
    } else if (isr_count != 1U ||
               EQep1Regs.QFLG.bit.PCE == 0U ||
               EQep1Regs.QFLG.bit.INT == 0U) {
        first_fail_code = EQEP_INT_GATE_FAIL_SOURCE_FLAG;
    }

    /* Releasing only the global latch must re-submit the pending PCE source. */
    EQep1Regs.QPOSINIT = EQEP_INT_GATE_STAGE_RETRIGGER;
    EQep1Regs.QCLR.bit.INT = 1U;
    if (first_fail_code == 0U && wait_for_isr_count(2U) == 0U) {
        first_fail_code = EQEP_INT_GATE_FAIL_RETRIGGER;
    }
    if (first_fail_code == 0U &&
        (isr_count != 2U ||
         EQep1Regs.QFLG.bit.PCE == 0U ||
         EQep1Regs.QFLG.bit.INT == 0U)) {
        first_fail_code = EQEP_INT_GATE_FAIL_RETRIGGER_STATE;
    }

    /* Completing service clears both latches and must leave a quiet window. */
    EQep1Regs.QPOSINIT = EQEP_INT_GATE_STAGE_CLEAR;
    EQep1Regs.QCLR.all = 0x0003U;
    DELAY_US(EQEP_INT_GATE_QUIET_US);
    if (first_fail_code == 0U &&
        (EQep1Regs.QFLG.bit.PCE != 0U ||
         EQep1Regs.QFLG.bit.INT != 0U)) {
        first_fail_code = EQEP_INT_GATE_FAIL_CLEAR_FLAGS;
    }
    if (first_fail_code == 0U && isr_count != 2U) {
        first_fail_code = EQEP_INT_GATE_FAIL_CLEAR_QUIET;
    }

    /* A new PCE event after the full clear must generate a fresh interrupt. */
    EQep1Regs.QPOSINIT = EQEP_INT_GATE_STAGE_REARM;
    EQep1Regs.QFRC.bit.PCE = 1U;
    if (first_fail_code == 0U && wait_for_isr_count(3U) == 0U) {
        first_fail_code = EQEP_INT_GATE_FAIL_REARM_ISR;
    }
    if (first_fail_code == 0U &&
        (isr_count != 3U ||
         EQep1Regs.QFLG.bit.PCE == 0U ||
         EQep1Regs.QFLG.bit.INT == 0U)) {
        first_fail_code = EQEP_INT_GATE_FAIL_REARM_STATE;
    }

    DINT;
    EQep1Regs.QEINT.all = 0x0000U;
    EQep1Regs.QCLR.all = 0x0FFFU;

    if (first_fail_code == 0U) {
        pass();
    } else {
        fail(first_fail_code);
    }

    while (1) {
    }
}
