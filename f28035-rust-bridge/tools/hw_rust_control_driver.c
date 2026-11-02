/* TI C only supplies test data and records Rust results; all three operations
 * (slice sum, enum dispatch, and their function calls) live in Rust.
 *
 * Pointer arguments are declared as C POINTERS, not `unsigned long`:
 * TI's EABI passes a pointer in XAR4/XAR5 while a 32-bit integer goes in ACC,
 * and the Rust side declares these parameters as `*const u16` (pointer pool).
 * Declaring them as integers made the two sides disagree on the register and
 * the callee read garbage -- the old backend masked this by routing pointers
 * through ACC.  Like every Rust-facing pointer they carry a LOGICAL BYTE
 * address, so the C side doubles its word addresses (same convention as
 * tools/hw_abi_driver.c). */
extern unsigned rust_control(const unsigned *logical_byte_ptr, unsigned len,
                             unsigned tag);
extern unsigned rust_sum_slice(const unsigned *logical_byte_ptr, unsigned len);
extern void hw_done(void);

#pragma DATA_SECTION(HW_RUST_RESULT, ".hw_result")
volatile unsigned HW_RUST_RESULT[6];

#pragma DATA_SECTION(HW_RUST_DATA, ".hw_result")
volatile unsigned HW_RUST_DATA[4];

unsigned main(void) {
    const unsigned *logical_ptr;
    HW_RUST_DATA[0] = 2;
    HW_RUST_DATA[1] = 4;
    HW_RUST_DATA[2] = 6;
    HW_RUST_DATA[3] = 8;
    /* TI C pointers are word addresses. Rust pointers use logical bytes. */
    logical_ptr = (const unsigned *)(((unsigned long)HW_RUST_DATA) * 2ul);
    HW_RUST_RESULT[0] = rust_control(logical_ptr, 4, 0);
    HW_RUST_RESULT[1] = rust_control(logical_ptr, 4, 1);
    HW_RUST_RESULT[2] = rust_control(logical_ptr, 4, 2);
    HW_RUST_RESULT[3] = rust_sum_slice(logical_ptr, 4);
    HW_RUST_RESULT[4] = HW_RUST_RESULT[0] + HW_RUST_RESULT[1] + HW_RUST_RESULT[2];
    HW_RUST_RESULT[5] = 0xB2;
    hw_done();
    return 0;
}
