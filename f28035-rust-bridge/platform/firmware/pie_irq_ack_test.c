#include "DSP28x_Project.h"
extern void rust_pie_irq_ack_setup(void);
volatile Uint16 called;
int main(void) {
    rust_pie_irq_ack_setup();
    called = 1U;
    for (;;) {}
}