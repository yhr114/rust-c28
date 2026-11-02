/* Core exercise group B (generic ABI): iterator adaptors over the
 * C-supplied slice, reached through the frozen logical-byte pointer ABI
 * (the driver doubles the TI word address).
 *
 * The pointer parameter MUST be declared as a C pointer, not `unsigned long`.
 * TI's EABI allocates argument registers positionally (AL, AH, XAR4, XAR5), so
 * `(unsigned long, unsigned)` puts the 32-bit value in ACC and the 16-bit one
 * in XAR4.  The Rust side declares `ptr: *const u16` and this backend uses a
 * class-based convention (pointers -> XAR4/XAR5, i16 -> AL/AH).  Declaring the
 * pointer as an integer therefore crossed the two conventions and the callee
 * read ptr=4 (the length) and len=0x800 (the pointer), which made every
 * adaptor iterate 2048 words from the wrong address (group B returned 11191
 * instead of 80).  Same contract as tools/hw_rust_control_driver.c. */
extern unsigned core_ex_iter_slice(const unsigned *logical_byte_ptr,
                                   unsigned len);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result_noinit")
volatile unsigned HW_CORE_RESULT[2];

#pragma DATA_SECTION(HW_CORE_DATA, ".hw_result_noinit")
volatile unsigned HW_CORE_DATA[4];

unsigned main(void) {
    const unsigned *logical_ptr;
    HW_CORE_DATA[0] = 2;
    HW_CORE_DATA[1] = 4;
    HW_CORE_DATA[2] = 6;
    HW_CORE_DATA[3] = 8;
    /* TI C pointers are word addresses. Rust pointers use logical bytes. */
    logical_ptr = (const unsigned *)(((unsigned long)HW_CORE_DATA) * 2ul);
    HW_CORE_RESULT[0] = core_ex_iter_slice(logical_ptr, 4);
    HW_CORE_RESULT[1] = 0xB3;
    hw_done();
    return 0;
}
