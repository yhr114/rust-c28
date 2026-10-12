#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()

#define QFLG_PCM_MASK 0x0100U

static volatile Uint32 sink32;
static volatile Uint16 sink16;

static void eqep_gpio_init(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

static void eqep_base_reset(void)
{
    EALLOW;
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EQep1Regs.QDECCTL.all = 0x0000U;
    EQep1Regs.QEPCTL.all  = 0x0000U;
    EQep1Regs.QCAPCTL.all = 0x0000U;
    EQep1Regs.QPOSCTL.all = 0x0000U;
    EQep1Regs.QEINT.all   = 0x0000U;
    EQep1Regs.QCLR.all    = 0x0FFFU;
    EQep1Regs.QCLR.bit.INT = 1U;
    EQep1Regs.QEPSTS.all  = 0x00F0U;
    EDIS;
}

static Uint16 wait_pcm(Uint32 timeout)
{
    while (timeout > 0UL) {
        if ((EQep1Regs.QFLG.all & QFLG_PCM_MASK) != 0U) {
            return 1U;
        }
        timeout--;
    }
    return 0U;
}

static void run_compare_pulse_stage(Uint16 sp_sel, Uint16 pc_pol,
                                    Uint16 pc_load, Uint16 pcshdw,
                                    Uint16 pcspw, Uint32 cmp,
                                    Uint16 fail_code)
{
    eqep_base_reset();

    EALLOW;
    EQep1Regs.QPOSMAX = 0x0000FFFFUL;
    EQep1Regs.QPOSCNT = cmp - 1UL;
    EQep1Regs.QPOSCMP = cmp;
    EQep1Regs.QDECCTL.bit.QSRC = 2U;
    EQep1Regs.QDECCTL.bit.SPSEL = sp_sel;
    EQep1Regs.QDECCTL.bit.SOEN = 1U;
    EQep1Regs.QPOSCTL.bit.PCSPW = pcspw;
    EQep1Regs.QPOSCTL.bit.PCLOAD = pc_load;
    EQep1Regs.QPOSCTL.bit.PCPOL = pc_pol;
    EQep1Regs.QPOSCTL.bit.PCSHDW = pcshdw;
    EQep1Regs.QPOSCTL.bit.PCE = 1U;
    EQep1Regs.QEINT.bit.PCM = 1U;
    EQep1Regs.QEPCTL.bit.PCRM = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;
    EDIS;

    if (wait_pcm(EQEP_PCOUT_POLL_TIMEOUT) == 0U) {
        fail(fail_code);
    }

    DELAY_US(EQEP_PCOUT_OBSERVE_US);

    sink32 = EQep1Regs.QPOSCNT;
    sink16 = EQep1Regs.QPOSCTL.all;
    sink16 = EQep1Regs.QDECCTL.all;

    EALLOW;
    EQep1Regs.QCLR.all = QFLG_PCM_MASK;
    EQep1Regs.QCLR.bit.INT = 1U;
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EDIS;
}

void main(void)
{
    InitSysCtrl();
    eqep_gpio_init();

    DINT;
    InitPieCtrl();
    IER = 0x0000U;
    IFR = 0x0000U;
    InitPieVectTable();

    run_compare_pulse_stage(1U, 0U, 0U, 0U, 1U, 4UL, EQEP_PCOUT_FAIL_PCM_A);
    run_compare_pulse_stage(1U, 1U, 1U, 0U, 2U, 5UL, EQEP_PCOUT_FAIL_PCM_B);
    run_compare_pulse_stage(0U, 0U, 0U, 1U, 3U, 6UL, EQEP_PCOUT_FAIL_PCM_C);
    run_compare_pulse_stage(0U, 1U, 1U, 1U, 4U, 7UL, EQEP_PCOUT_FAIL_PCM_D);

    pass();

    while (1) {
    }
}
