#include "DSP28x_Project.h"

/* MUX round-trip is split into two Rust-authored Safe HAL mirror functions so
 * the harness can snapshot GPIO0's MUX field IN THE MIDDLE of the 0->1->0
 * sequence.  A single call could only show the final 0 and could not prove the
 * intermediate 1 (EPWM1A) ever appeared.
 *
 *   phase1: rust_gpio0_mux_to_epwm1a()  -> snapshot GPAMUX1.GPIO0 (expect 1)
 *   reset  the one-shot peripheral lock (extern volatile, exposed by the C
 *          bridge) so the phase-2 mirror may take() it again
 *   phase2: rust_gpio0_mux_restore_gpio() -> snapshot GPAMUX1.GPIO0 (expect 0)
 */
extern void rust_gpio0_mux_to_epwm1a(void);
extern void rust_gpio0_mux_restore_gpio(void);
extern volatile Uint16 f28035_peripherals_taken;

/* Set after the Rust-authored functions return; inspect through XDS. */
volatile Uint16 rust_gpio0_mux_called;
volatile Uint16 rust_gpio0_mux_phase1_mux;   /* GPAMUX1.GPIO0 after phase 1 */
volatile Uint16 rust_gpio0_mux_phase2_mux;   /* GPAMUX1.GPIO0 after phase 2 */

int main(void)
{
    /* Phase 1: GPIO0 MUX 0 -> 1 (EPWM1A). */
    rust_gpio0_mux_to_epwm1a();
    rust_gpio0_mux_phase1_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO0;

    /* Release the one-shot peripheral claim so phase 2 may take() again. */
    f28035_peripherals_taken = 0U;

    /* Phase 2: GPIO0 MUX 1 -> 0 (GPIO). */
    rust_gpio0_mux_restore_gpio();
    rust_gpio0_mux_phase2_mux = GpioCtrlRegs.GPAMUX1.bit.GPIO0;

    rust_gpio0_mux_called = 1U;

    for (;;) {
    }
}
