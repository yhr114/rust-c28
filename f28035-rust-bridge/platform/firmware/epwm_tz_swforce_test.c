#include "DSP28x_Project.h"
extern void rust_epwm_tz_swforce_setup(void);
extern Uint16 f28035_epwm1_period(void);
extern Uint16 f28035_epwm1_compare(void);
extern Uint16 f28035_epwm1_tzsel(void);
extern Uint16 f28035_epwm1_tzctl(void);

volatile Uint16 tz_called, tz_tbprd, tz_cmpa, tz_tzsel, tz_tzctl;

int main(void) {
    rust_epwm_tz_swforce_setup();
    tz_tbprd = f28035_epwm1_period();
    tz_cmpa  = f28035_epwm1_compare();
    tz_tzsel = f28035_epwm1_tzsel();
    tz_tzctl = f28035_epwm1_tzctl();
    tz_called = 1U;
    for (;;) {}
}
