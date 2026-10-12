#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define RESET_STATE ((volatile Uint16 *)EQEP_RESET_FSM_STATE_ADDR)
#define RESET_MAGIC RESET_STATE[0]
#define RESET_COUNT RESET_STATE[1]
#define RESET_COUNT_INV RESET_STATE[2]

static void init_eqep_gpio(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

static Uint16 load_reset_count(void)
{
    Uint16 count = RESET_COUNT;

    if (RESET_MAGIC != EQEP_RESET_FSM_MAGIC ||
        RESET_COUNT_INV != (Uint16)(~count) ||
        count > EQEP_RESET_FSM_STAGE_COUNT) {
        RESET_MAGIC = EQEP_RESET_FSM_MAGIC;
        RESET_COUNT = 0U;
        RESET_COUNT_INV = (Uint16)(~0U);
        count = 0U;
    }

    return count;
}

static void store_reset_count(Uint16 count)
{
    RESET_MAGIC = EQEP_RESET_FSM_MAGIC;
    RESET_COUNT = count;
    RESET_COUNT_INV = (Uint16)(~count);
}

static void init_eqep_stage(Uint16 stage)
{
    EALLOW;
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.all = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QEINT.all = 0x0000U;
    EQep1Regs.QCLR.all = 0x0FFFU;
    EQep1Regs.QCLR.bit.INT = 1U;
    EQep1Regs.QPOSCNT = 0UL;
    EQep1Regs.QPOSMAX = 0xFFFFFFFFUL;
    EQep1Regs.QPOSINIT = EQEP_RESET_FSM_TAG_BASE + (Uint32)stage;
    EQep1Regs.QEPCTL.bit.PCRM = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;
    EDIS;
}

void main(void)
{
    Uint16 stage;

    InitSysCtrl();
    init_eqep_gpio();

    DINT;
    InitPieCtrl();
    IER = 0x0000U;
    IFR = 0x0000U;
    InitPieVectTable();

    stage = load_reset_count();
    if (stage >= EQEP_RESET_FSM_STAGE_COUNT) {
        RESET_MAGIC = 0U;
        test_runtime_pass();
    }

    init_eqep_stage(stage);
    store_reset_count((Uint16)(stage + 1U));

    while (1) {
    }
}
