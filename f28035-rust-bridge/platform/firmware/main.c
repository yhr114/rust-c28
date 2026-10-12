#include "DSP28x_Project.h"

/* Implemented by rust-api/src/application.rs after Rust-to-C28x codegen. */
extern void rust_main(void);

int main(void)
{
    rust_main();

    /* rust_main never returns. Keep a defensive fallback for the C ABI. */
    for (;;) {
    }
}

