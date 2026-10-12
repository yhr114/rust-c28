/*
 * Purpose: Verify EPWM1 CMPA boundary behavior in one matrix case.
 * - Mode: up-count
 * - AQ: ZRO=set, CAU=clear
 * - Segments: CMPA=0, 1, TBPRD-1, TBPRD
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "epwm_cmp_boundary_matrix currently supports VERSION=28035 only"
#endif

#include "device_28035.h"

typedef struct {
    unsigned int cmpa;
    unsigned int run_us;
} epwm_cmp_boundary_segment_t;

static const epwm_cmp_boundary_segment_t g_cmp_boundary_segments[] = {
    {EPWM_CMP_BOUNDARY_CMPA_ZERO, EPWM_CMP_BOUNDARY_SEGMENT_RUN_US},
    {EPWM_CMP_BOUNDARY_CMPA_ONE, EPWM_CMP_BOUNDARY_SEGMENT_RUN_US},
    {EPWM_CMP_BOUNDARY_CMPA_PRD_MINUS1, EPWM_CMP_BOUNDARY_SEGMENT_RUN_US},
    {EPWM_CMP_BOUNDARY_CMPA_PRD, EPWM_CMP_BOUNDARY_FINAL_RUN_US},
};

volatile unsigned int g_epwm_cmp_boundary_stage;
volatile unsigned int g_epwm_cmp_boundary_cmpa_readback[EPWM_CMP_BOUNDARY_STAGE_COUNT];

static void epwm1_stop_reset(void)
{
    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EDIS;
}

static void epwm1_program_common(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK = 1U;

    EPwm1Regs.TBCTL.all = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTL.bit.PHSEN = 0U;
    EPwm1Regs.TBCTL.bit.HSPCLKDIV = 0U;
    EPwm1Regs.TBCTL.bit.CLKDIV = 0U;
    EPwm1Regs.TBPRD = EPWM_CMP_BOUNDARY_TBPRD_TICKS;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.CMPA.half.CMPA = EPWM_CMP_BOUNDARY_CMPA_ZERO;
    EPwm1Regs.AQCTLA.all = 0x0012U;
    EPwm1Regs.AQCTLB.all = 0x0000U;
    EDIS;

    epwm1_stop_reset();
}

static void epwm1_apply_segment(unsigned int stage)
{
    const epwm_cmp_boundary_segment_t *segment = &g_cmp_boundary_segments[stage];

    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.TBPRD = EPWM_CMP_BOUNDARY_TBPRD_TICKS;
    EPwm1Regs.CMPA.half.CMPA = segment->cmpa;
    EPwm1Regs.AQCTLA.all = 0x0012U;
    EPwm1Regs.AQCTLB.all = 0x0000U;
    g_epwm_cmp_boundary_stage = stage;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 0U;
    EDIS;

    g_epwm_cmp_boundary_cmpa_readback[stage] = EPwm1Regs.CMPA.half.CMPA;
    board_delay_us(segment->run_us);
}

static void epwm1_check_segment(unsigned int stage)
{
    const epwm_cmp_boundary_segment_t *segment = &g_cmp_boundary_segments[stage];

    if ((EPwm1Regs.TBCTL.bit.CTRMODE != 0U) ||
        (EPwm1Regs.TBPRD != EPWM_CMP_BOUNDARY_TBPRD_TICKS) ||
        (EPwm1Regs.CMPA.half.CMPA != segment->cmpa) ||
        (g_epwm_cmp_boundary_cmpa_readback[stage] != segment->cmpa) ||
        (EPwm1Regs.AQCTLA.all != 0x0012U) ||
        (EPwm1Regs.AQCTLB.all != 0x0000U)) {
        test_runtime_fail(EPWM_CMP_BOUNDARY_FAIL_STAGE_READBACK);
    }
}

void main(void)
{
    unsigned int i;

    board_demo_init();
    gpio_case_epwm1a_mux_init();
    epwm1_program_common();

    if (GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 1U) {
        test_runtime_fail(EPWM_CMP_BOUNDARY_FAIL_GPIO_MUX);
    }

    for (i = 0U; i < EPWM_CMP_BOUNDARY_STAGE_COUNT; ++i) {
        epwm1_apply_segment(i);
        epwm1_check_segment(i);
    }

    if ((EPwm1Regs.TBCTL.bit.CTRMODE != 0U) ||
        (EPwm1Regs.TBPRD != EPWM_CMP_BOUNDARY_TBPRD_TICKS) ||
        (EPwm1Regs.CMPA.half.CMPA != EPWM_CMP_BOUNDARY_CMPA_PRD) ||
        (EPwm1Regs.AQCTLA.all != 0x0012U)) {
        test_runtime_fail(EPWM_CMP_BOUNDARY_FAIL_FINAL_READBACK);
    }

    test_runtime_pass();
}
