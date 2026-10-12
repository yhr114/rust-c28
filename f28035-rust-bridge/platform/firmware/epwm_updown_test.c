#include "DSP28x_Project.h"
extern void rust_epwm_updown_aq_setup(void);
extern Uint16 f28035_epwm1_period(void);
extern Uint16 f28035_epwm1_compare(void);
extern Uint16 f28035_epwm1_aqctla(void);
extern Uint16 f28035_epwm1_counter_mode(void);

volatile Uint16 ud_called, ud_tbprd, ud_cmpa, ud_aqctla, ud_ctr;

int main(void) {
    rust_epwm_updown_aq_setup();
    ud_tbprd  = f28035_epwm1_period();
    ud_cmpa   = f28035_epwm1_compare();
    ud_aqctla = f28035_epwm1_aqctla();
    ud_ctr    = f28035_epwm1_counter_mode();
    ud_called = 1U;
    for (;;) {}
}
