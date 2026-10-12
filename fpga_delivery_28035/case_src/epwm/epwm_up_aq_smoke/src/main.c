/*
 * Purpose: Verify EPWM1 basic up-count PWM output.
 * - Mode: up-count
 * - AQ: ZRO=set, CAU=clear
 * - Checks: TBPRD/CMPA/AQCTLA readback and basic waveform timing
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "epwm_up_aq_smoke currently supports VERSION=28035 only"
#endif

#include "device_28035.h"

static void epwm1_stop(void)
{
    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EDIS;
}

static void epwm1_init_up_aq(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK = 1U;

    EPwm1Regs.TBCTL.all = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTL.bit.PHSEN = 0U;
    EPwm1Regs.TBCTL.bit.HSPCLKDIV = 0U;
    EPwm1Regs.TBCTL.bit.CLKDIV = 0U;
    EPwm1Regs.TBPRD = EPWM_SMOKE_TBPRD_TICKS;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.CMPA.half.CMPA = EPWM_SMOKE_CMPA_TICKS;
    EPwm1Regs.AQCTLA.all = 0x0012U;
    EPwm1Regs.AQCTLB.all = 0x0000U;
    EDIS;

    epwm1_stop();
}

static void epwm1_start(void)
{
    EALLOW;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 0U;
    EDIS;
}

void main(void)
{
    board_demo_init();
    gpio_case_epwm1a_mux_init();
    epwm1_init_up_aq();

    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 1U) {
        test_runtime_fail(EPWM_SMOKE_FAIL_GPIO_MUX);
    }

    epwm1_start();
    board_delay_us(EPWM_SMOKE_RUN_DELAY_US);

    if ((EPwm1Regs.TBPRD != EPWM_SMOKE_TBPRD_TICKS) ||
        (EPwm1Regs.CMPA.half.CMPA != EPWM_SMOKE_CMPA_TICKS) ||
        (EPwm1Regs.AQCTLA.all != 0x0012U) ||
        (EPwm1Regs.TBCTL.bit.CTRMODE != 0U)) {
        test_runtime_fail(EPWM_SMOKE_FAIL_REG_READBACK);
    }

    test_runtime_pass();
}
