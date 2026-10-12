#include "DSP28x_Project.h"
extern void rust_epwm_event_int_soca_setup(void);
extern Uint16 f28035_epwm1_period(void);
extern Uint16 f28035_epwm1_compare(void);
extern Uint16 f28035_epwm1_aqctla(void);
extern Uint16 f28035_epwm1_counter_mode(void);
extern Uint16 f28035_epwm1_event_int_enabled(void);
extern Uint16 f28035_epwm1_event_soca_enabled(void);
extern Uint16 f28035_epwm1_event_int_period(void);
extern Uint16 f28035_epwm1_event_soca_period(void);

volatile Uint16 ev_called;
volatile Uint16 ev_tbprd, ev_cmpa, ev_aqctla, ev_ctr_mode;
volatile Uint16 ev_int_en, ev_soca_en, ev_int_prd, ev_soca_prd;

int main(void) {
    rust_epwm_event_int_soca_setup();
    ev_tbprd    = f28035_epwm1_period();
    ev_cmpa     = f28035_epwm1_compare();
    ev_aqctla   = f28035_epwm1_aqctla();
    ev_ctr_mode = f28035_epwm1_counter_mode();
    ev_int_en   = f28035_epwm1_event_int_enabled();
    ev_soca_en  = f28035_epwm1_event_soca_enabled();
    ev_int_prd  = f28035_epwm1_event_int_period();
    ev_soca_prd = f28035_epwm1_event_soca_period();
    ev_called = 1U;
    for (;;) {}
}
