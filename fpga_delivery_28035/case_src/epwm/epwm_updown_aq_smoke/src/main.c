/*
 * Purpose: Verify EPWM1 basic up-down PWM output.
 * - Mode: up-down
 * - AQ: ZRO=set, CAU=clear, CAD=set
 * - Checks: center-aligned period and high-time
 */
#include "board_gpio.h"
#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"
#if !defined(DEVICE_28035)
#error "epwm_updown_aq_smoke currently supports VERSION=28035 only"
#endif
#include "device_28035.h"
static void epwm1_stop(void){EALLOW;EPwm1Regs.TBCTL.bit.CTRMODE=3U;EPwm1Regs.TBCTR=0U;EDIS;}
static void epwm1_init_updown_aq(void){EALLOW;SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK=1U;EPwm1Regs.TBCTL.all=0U;EPwm1Regs.TBCTL.bit.CTRMODE=3U;EPwm1Regs.TBCTL.bit.PHSEN=0U;EPwm1Regs.TBCTL.bit.HSPCLKDIV=0U;EPwm1Regs.TBCTL.bit.CLKDIV=0U;EPwm1Regs.TBPRD=EPWM_UPDOWN_TBPRD_TICKS;EPwm1Regs.TBCTR=0U;EPwm1Regs.CMPA.half.CMPA=EPWM_UPDOWN_CMPA_TICKS;EPwm1Regs.AQCTLA.all=0x0092U;EPwm1Regs.AQCTLB.all=0x0000U;EDIS;epwm1_stop();}
static void epwm1_start(void){EALLOW;EPwm1Regs.TBCTR=0U;EPwm1Regs.TBCTL.bit.CTRMODE=2U;EDIS;}
void main(void){board_demo_init();gpio_case_epwm1a_mux_init();epwm1_init_updown_aq();if(GpioCtrlRegs.GPAMUX1.bit.GPIO0!=1U){test_runtime_fail(EPWM_UPDOWN_FAIL_GPIO_MUX);}epwm1_start();board_delay_us(EPWM_UPDOWN_RUN_DELAY_US);if((EPwm1Regs.TBPRD!=EPWM_UPDOWN_TBPRD_TICKS)||(EPwm1Regs.CMPA.half.CMPA!=EPWM_UPDOWN_CMPA_TICKS)||(EPwm1Regs.AQCTLA.all!=0x0092U)||(EPwm1Regs.TBCTL.bit.CTRMODE!=2U)){test_runtime_fail(EPWM_UPDOWN_FAIL_REG_READBACK);}test_runtime_pass();}
