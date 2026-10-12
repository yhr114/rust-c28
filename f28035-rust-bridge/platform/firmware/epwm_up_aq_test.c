#include "DSP28x_Project.h"

/* epwm_up_aq_smoke: Rust-authored Safe HAL mirror configures ePWM1 in
 * up-count mode (period=99, compare=40, active-high AQ on zero).  The C
 * harness snapshots the registers after return so DSS can verify them:
 *
 *   TBPRD   == 99
 *   CMPA    == 40
 *   AQCTLA  == 0x0012  (zero -> clear CAU=0, zero -> set CAU=1 ... active-high)
 *   CTRMODE == 0       (up-count)
 *   GPIO0 MUX == 1     (EPWM1A)
 */
extern void rust_epwm_up_aq_setup(void);

volatile Uint16 rust_epwm_up_aq_called;
volatile Uint16 rust_epwm_up_aq_tbprd;
volatile Uint16 rust_epwm_up_aq_cmpa;
volatile Uint16 rust_epwm_up_aq_aqctla;
volatile Uint16 rust_epwm_up_aq_ctr_mode;
volatile Uint16 rust_epwm_up_aq_gpio0_mux;

int main(void)
{
    rust_epwm_up_aq_setup();

    rust_epwm_up_aq_tbprd    = EPwm1Regs.TBPRD;
    rust_epwm_up_aq_cmpa     = EPwm1Regs.CMPA.half.CMPA;
    rust_epwm_up_aq_aqctla   = EPwm1Regs.AQCTLA.all;
    rust_epwm_up_aq_ctr_mode = EPwm1Regs.TBCTL.bit.CTRMODE;
    rust_epwm_up_aq_gpio0_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO0;

    rust_epwm_up_aq_called = 1U;

    for (;;) {
    }
}
