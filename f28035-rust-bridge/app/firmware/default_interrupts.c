#include "f28035_bridge.h"

/* Default callback for cases that do not exercise Timer0 interrupts. */
void rust_timer0_interrupt(void)
{
    f28035_timer0_ack();
}
