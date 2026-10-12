#include <limits.h>

#if USHRT_MAX != 65535U
#error "The Rust u16 ABI test requires a 16-bit unsigned short"
#endif

typedef unsigned short rust_u16;

extern rust_u16 rust_add(rust_u16 a, rust_u16 b);

/* Inspect these symbols with CCS/XDS after the program reaches the loop. */
volatile rust_u16 rust_add_actual;
volatile rust_u16 rust_add_expected;
volatile rust_u16 rust_add_pass;

int main(void)
{
    rust_add_expected = 1U;
    rust_add_actual = rust_add(65535U, 2U);
    rust_add_pass = (rust_add_actual == rust_add_expected) ? 1U : 0U;

    for (;;) {
    }
}
