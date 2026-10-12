/*
 * Purpose: Verify EPWM1 trip-zone one-shot trip from external TZ1n input.
 * - C configures GPIO15 as TZ1n and enables TZSEL.OSHT1.
 * - UVM sequence drives the GPIO15/TZ1n pad low, then releases it high.
 * - Checks: TZFLG.OST set/clear and UVM-visible forced-low/recovery waveform.
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "epwm_tz_external_tz1_ost currently supports VERSION=28035 only"
#endif

#include "device_28035.h"

#define EPWM_TZSEL_OFFSET             0x0012U
#define EPWM_TZCTL_OFFSET             0x0014U
#define EPWM_TZEINT_OFFSET            0x0015U
#define EPWM_TZFLG_OFFSET             0x0016U
#define EPWM_TZCLR_OFFSET             0x0017U

#define EPWM_TZSEL_OSHT1              0x0100U
#define EPWM_TZ_OST_BIT               0x0004U
#define EPWM_TZ_INT_BIT               0x0001U
#define EPWM_TZ_FORCE_LOW_TZA_TZB     0x000AU

static volatile Uint16 * const epwm1_reg = (volatile Uint16 *)&EPwm1Regs;

static void gpio_case_epwm1b_mux_init_local(void)
{
    EALLOW;
    GpioCtrlRegs.GPAMUX1.bit.GPIO1 = 1U;
    EDIS;
}

static void gpio_case_tz1n_mux_init_local(void)
{
    EALLOW;
    GpioCtrlRegs.GPADIR.bit.GPIO15 = 0U;
    GpioCtrlRegs.GPAQSEL1.bit.GPIO15 = 3U;
    GpioCtrlRegs.GPAMUX1.bit.GPIO15 = 1U;
    EDIS;
}

static Uint16 epwm1_tz_read(Uint16 offset)
{
    return epwm1_reg[offset];
}

static void epwm1_tz_write(Uint16 offset, Uint16 value)
{
    epwm1_reg[offset] = value;
}

static void epwm1_stop(void)
{
    EALLOW;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTR = 0U;
    EDIS;
}

static void epwm1_init_external_tz1_ost(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK = 1U;

    EPwm1Regs.TBCTL.all = 0U;
    EPwm1Regs.TBCTL.bit.CTRMODE = 3U;
    EPwm1Regs.TBCTL.bit.PHSEN = 0U;
    EPwm1Regs.TBCTL.bit.HSPCLKDIV = 0U;
    EPwm1Regs.TBCTL.bit.CLKDIV = 0U;
    EPwm1Regs.TBPRD = EPWM_TZ_EXT_TBPRD_TICKS;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.CMPA.half.CMPA = EPWM_TZ_EXT_CMPA_TICKS;
    EPwm1Regs.AQCTLA.all = 0x0012U;
    EPwm1Regs.AQCTLB.all = 0x0012U;

    epwm1_tz_write(EPWM_TZSEL_OFFSET, EPWM_TZSEL_OSHT1);
    epwm1_tz_write(EPWM_TZCTL_OFFSET, EPWM_TZ_FORCE_LOW_TZA_TZB);
    epwm1_tz_write(EPWM_TZEINT_OFFSET, EPWM_TZ_OST_BIT);
    epwm1_tz_write(EPWM_TZCLR_OFFSET, EPWM_TZ_OST_BIT | EPWM_TZ_INT_BIT);
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

static void epwm1_clear_ost(void)
{
    EALLOW;
    epwm1_tz_write(EPWM_TZCLR_OFFSET, EPWM_TZ_OST_BIT | EPWM_TZ_INT_BIT);
    EDIS;
}

static Uint16 wait_tzflg_ost(Uint16 expect_set)
{
    Uint16 i;

    for (i = 0U; i < EPWM_TZ_EXT_POLL_LIMIT; i++) {
        Uint16 set = (epwm1_tz_read(EPWM_TZFLG_OFFSET) & EPWM_TZ_OST_BIT) ? 1U : 0U;
        if (set == expect_set) {
            return 1U;
        }
    }
    return 0U;
}

void main(void)
{
    board_demo_init();
    gpio_case_epwm1a_mux_init();
    gpio_case_epwm1b_mux_init_local();
    gpio_case_tz1n_mux_init_local();
    epwm1_init_external_tz1_ost();

    if ((GpioCtrlRegs.GPAMUX1.bit.GPIO0 != 1U) ||
        (GpioCtrlRegs.GPAMUX1.bit.GPIO1 != 1U) ||
        (GpioCtrlRegs.GPAMUX1.bit.GPIO15 != 1U) ||
        (GpioCtrlRegs.GPADIR.bit.GPIO15 != 0U) ||
        (GpioCtrlRegs.GPAQSEL1.bit.GPIO15 != 3U)) {
        test_runtime_fail(EPWM_TZ_EXT_FAIL_GPIO_MUX);
    }

    epwm1_start();
    board_delay_us(EPWM_TZ_EXT_PRETRIP_DELAY_US);

    if ((EPwm1Regs.TBPRD != EPWM_TZ_EXT_TBPRD_TICKS) ||
        (EPwm1Regs.CMPA.half.CMPA != EPWM_TZ_EXT_CMPA_TICKS) ||
        (EPwm1Regs.AQCTLA.all != 0x0012U) ||
        (epwm1_tz_read(EPWM_TZSEL_OFFSET) != EPWM_TZSEL_OSHT1) ||
        (epwm1_tz_read(EPWM_TZCTL_OFFSET) != EPWM_TZ_FORCE_LOW_TZA_TZB) ||
        ((epwm1_tz_read(EPWM_TZEINT_OFFSET) & EPWM_TZ_OST_BIT) == 0U) ||
        (EPwm1Regs.TBCTL.bit.CTRMODE != 0U)) {
        test_runtime_fail(EPWM_TZ_EXT_FAIL_REG_READBACK);
    }

    if (!wait_tzflg_ost(1U)) {
        test_runtime_fail(EPWM_TZ_EXT_FAIL_OST_NOT_SET);
    }

    board_delay_us(EPWM_TZ_EXT_TRIP_HOLD_DELAY_US);
    epwm1_clear_ost();
    if (!wait_tzflg_ost(0U)) {
        test_runtime_fail(EPWM_TZ_EXT_FAIL_OST_NOT_CLEAR);
    }

    board_delay_us(EPWM_TZ_EXT_RECOVERY_DELAY_US);
    test_runtime_pass();
}
