/* TI C driver for the B-1 direct-object argument-ABI RAM/JTAG sample.
 * Pointer arguments are declared as C pointers (TI passes them in XAR4);
 * like every Rust-facing pointer they carry a LOGICAL BYTE address, so the
 * C side doubles its word addresses.  The aggregate-return (sret) case runs
 * Rust->Rust inside the callee because the hidden sret pointer follows
 * different address conventions on the two sides (TI C passes a raw word
 * address; the Rust callee halves it).
 *
 * All Rust calls happen BEFORE any result store: the .hw_result section lives
 * close to the stack, and intermediate result slots were observed being
 * clobbered by the callees' frames. */
extern unsigned long rust_sret_self_check(unsigned long ptr, unsigned long len);
extern unsigned long rust_read_ptr(const unsigned long *logical_byte_ptr);
extern unsigned long rust_mixed(unsigned short a, const unsigned short *logical_byte_ptr,
                                unsigned long b);
extern unsigned long rust_apply(unsigned long (*apply)(unsigned long),
                                unsigned long value);
extern unsigned long rust_stk32_echo(unsigned long a, unsigned long b);
extern unsigned long rust_stack_args(unsigned short a, unsigned short b,
                                    unsigned short c, unsigned short d,
                                    unsigned short e, unsigned long f);
extern unsigned long rust_bb_args(unsigned short a, unsigned short b,
                                  unsigned short c, unsigned short d,
                                  unsigned short e, unsigned long f,
                                  unsigned short sel);
extern unsigned long rust_nested(unsigned short a, unsigned short b,
                                 unsigned short c, unsigned short d,
                                 unsigned short e, unsigned long f);
extern unsigned long ti_double(unsigned long value);
extern void hw_done(void);

#pragma DATA_SECTION(HW_RUST_RESULT, ".hw_result")
volatile unsigned long HW_RUST_RESULT[12];

#pragma DATA_SECTION(HW_RUST_DATA, ".hw_result")
volatile unsigned short HW_RUST_DATA[4];

unsigned long ti_double(unsigned long value) {
    return value * 2ul;
}

unsigned main(void) {
    unsigned long logical_ptr;
    unsigned long sret_sum;
    unsigned long dot_value;
    unsigned long mixed_sum;
    unsigned long applied;
    unsigned long stack_sum;
    unsigned long bb_odd;
    unsigned long bb_even;
    unsigned long nested;
    unsigned long stk32_echo;

    /* word 0/1: a u32 object 0x00001234; word 2: the u16 seen by rust_mixed */
    HW_RUST_DATA[0] = 0x1234;
    HW_RUST_DATA[1] = 0;
    HW_RUST_DATA[2] = 7;
    logical_ptr = ((unsigned long)HW_RUST_DATA) * 2ul; /* word -> logical bytes */

    /* 1. aggregate return: sret path exercised Rust->Rust (XAR6).
     * Checksum is ptr*3+len so a swapped field pair is detectable. */
    sret_sum = rust_sret_self_check(0x1111, 0x2222);

    /* 2. pointer argument: data pointer travels in XAR4 (reads the u32) */
    dot_value = rust_read_ptr((const unsigned long *)logical_ptr);

    /* 3. mixed (i16, ptr, i32): a=AR5, p=XAR4, b=ACC (reads word 2 = 7) */
    mixed_sum = rust_mixed(1, (const unsigned short *)(logical_ptr + 4), 2);

    /* 4. indirect call: function pointer in XAR4, LCR *XARn.
     * Rust function pointers are logical byte addresses (ABI L1-1), so the
     * TI word address of ti_double must be doubled here as well. */
    stack_sum = rust_stack_args(1, 2, 3, 4, 5, 6);
    applied = rust_apply(
        (unsigned long (*)(unsigned long))((unsigned long)ti_double * 2ul), 21);

    /* 5. cross-basic-block stack access: the branch blocks read the spilled
     *    stack arguments while the prologue has saved a callee-saved register
     *    (the inner call makes this function non-leaf). */
    bb_odd = rust_bb_args(1, 2, 3, 4, 5, 6, 3);   /* (a+e+f) + inner = 33 */
    bb_even = rust_bb_args(1, 2, 3, 4, 5, 6, 4);  /* (b+c+f) + inner = 32 */

    /* 6. nested calls: two successive outgoing argument areas while the
     *    incoming arguments (read after both calls) must survive. */
    nested = rust_nested(1, 2, 3, 4, 5, 6);       /* 21*3 + 21 + 6    = 90 */

    /* 7. C->Rust 32-bit stack argument: distinctive halves, returned as-is */
    stk32_echo = rust_stk32_echo(0, 0x12345678);   /* must stay 0x12345678 */

    HW_RUST_RESULT[0] = sret_sum;
    HW_RUST_RESULT[1] = dot_value;
    HW_RUST_RESULT[2] = mixed_sum;
    HW_RUST_RESULT[3] = applied;
    HW_RUST_RESULT[4] = stack_sum;
    HW_RUST_RESULT[5] = bb_odd;
    HW_RUST_RESULT[6] = bb_even;
    HW_RUST_RESULT[7] = nested;
    HW_RUST_RESULT[8] = 0xAB;
    HW_RUST_RESULT[9] = stk32_echo;
    hw_done();
    return 0;
}
