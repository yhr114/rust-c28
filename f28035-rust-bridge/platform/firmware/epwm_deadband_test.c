#include "DSP28x_Project.h"
extern void rust_epwm_deadband_setup(void);
extern Uint16 f28035_epwm1_period(void);
extern Uint16 f28035_epwm1_compare(void);
extern Uint16 f28035_epwm1_dbctl(void);
extern Uint16 f28035_epwm1_dbred(void);
extern Uint16 f28035_epwm1_dbfed(void);

volatile Uint16 db_called, db_tbprd, db_cmpa, db_dbctl, db_dbred, db_dbfed;

int main(void) {
    rust_epwm_deadband_setup();
    db_tbprd = f28035_epwm1_period();
    db_cmpa  = f28035_epwm1_compare();
    db_dbctl = f28035_epwm1_dbctl();
    db_dbred = f28035_epwm1_dbred();
    db_dbfed = f28035_epwm1_dbfed();
    db_called = 1U;
    for (;;) {}
}
