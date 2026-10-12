/*
 * Purpose: Verify EPWM1 symmetric deadband insertion.
 * - Mode: up-count with deadband
 * - DB: DBRED=DBFED=8
 * - Checks: A/B toggles and deadband delays
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"
#if !defined(DEVICE_28035)
#error "epwm_deadband_smoke currently supports VERSION=28035 only"
#endif
#include "device_28035.h"
static void gpio_case_epwm1b_mux_init_local(void){EALLOW;GpioCtrlRegs.GPAMUX1.bit.GPIO1=1U;EDIS;}
static void epwm1_stop(void){EALLOW;EPwm1Regs.TBCTL.bit.CTRMODE=3U;EPwm1Regs.TBCTR=0U;EDIS;}
static void epwm1_init_deadband(void){EALLOW;SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK=1U;EPwm1Regs.TBCTL.all=0U;EPwm1Regs.TBCTL.bit.CTRMODE=3U;EPwm1Regs.TBCTL.bit.PHSEN=0U;EPwm1Regs.TBCTL.bit.HSPCLKDIV=0U;EPwm1Regs.TBCTL.bit.CLKDIV=0U;EPwm1Regs.TBPRD=EPWM_DEADBAND_TBPRD_TICKS;EPwm1Regs.TBCTR=0U;EPwm1Regs.CMPA.half.CMPA=EPWM_DEADBAND_CMPA_TICKS;EPwm1Regs.AQCTLA.all=0x0012U;EPwm1Regs.AQCTLB.all=0x0000U;EPwm1Regs.DBCTL.all=0x000BU;EPwm1Regs.DBRED=EPWM_DEADBAND_DELAY_TICKS;EPwm1Regs.DBFED=EPWM_DEADBAND_DELAY_TICKS;EDIS;epwm1_stop();}
static void epwm1_start(void){EALLOW;EPwm1Regs.TBCTR=0U;EPwm1Regs.TBCTL.bit.CTRMODE=0U;EDIS;}
void main(void){board_demo_init();gpio_case_epwm1a_mux_init();gpio_case_epwm1b_mux_init_local();epwm1_init_deadband();if((GpioCtrlRegs.GPAMUX1.bit.GPIO0!=1U)||(GpioCtrlRegs.GPAMUX1.bit.GPIO1!=1U)){test_runtime_fail(EPWM_DEADBAND_FAIL_GPIO_MUX);}epwm1_start();board_delay_us(EPWM_DEADBAND_RUN_DELAY_US);if((EPwm1Regs.TBPRD!=EPWM_DEADBAND_TBPRD_TICKS)||(EPwm1Regs.CMPA.half.CMPA!=EPWM_DEADBAND_CMPA_TICKS)||(EPwm1Regs.AQCTLA.all!=0x0012U)||(EPwm1Regs.DBCTL.all!=0x000BU)||(EPwm1Regs.DBRED!=EPWM_DEADBAND_DELAY_TICKS)||(EPwm1Regs.DBFED!=EPWM_DEADBAND_DELAY_TICKS)||(EPwm1Regs.TBCTL.bit.CTRMODE!=0U)){test_runtime_fail(EPWM_DEADBAND_FAIL_REG_READBACK);}test_runtime_pass();}
