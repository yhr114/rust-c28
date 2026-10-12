#include "DSP28x_Project.h"
extern void rust_epwm_event_socb_setup(void);
extern Uint16 f28035_epwm1_period(void);
extern Uint16 f28035_epwm1_compare(void);
extern Uint16 f28035_epwm1_aqctla(void);
extern Uint16 f28035_epwm1_counter_mode(void);
extern Uint16 f28035_epwm1_event_socb_enabled(void);
extern Uint16 f28035_epwm1_event_socb_period(void);

volatile Uint16 rust_epwm_socb_called;
volatile Uint16 rust_epwm_socb_tbprd;
volatile Uint16 rust_epwm_socb_cmpa;
volatile Uint16 rust_epwm_socb_aqctla;
volatile Uint16 rust_epwm_socb_ctr_mode;
volatile Uint16 rust_epwm_socb_socb_en;
volatile Uint16 rust_epwm_socb_socb_prd;

int main(void) {
    rust_epwm_event_socb_setup();
    rust_epwm_socb_tbprd     = f28035_epwm1_period();
    rust_epwm_socb_cmpa      = f28035_epwm1_compare();
    rust_epwm_socb_aqctla    = f28035_epwm1_aqctla();
    rust_epwm_socb_ctr_mode  = f28035_epwm1_counter_mode();
    rust_epwm_socb_socb_en   = f28035_epwm1_event_socb_enabled();
    rust_epwm_socb_socb_prd  = f28035_epwm1_event_socb_period();
    rust_epwm_socb_called = 1U;
    for (;;) {}
}
