/* Core exercise group B2 (generic ABI): second half of the iterator adaptors
 * over the C-supplied slice (enumerate/fold, zip/skip/map/sum, rev/copied/sum),
 * reached through the frozen logical-byte pointer ABI (the driver doubles the
 * TI word address).  Split from group B so each image fits the 0x2000-word
 * F28035 program RAM.
 *
 * The pointer parameter is declared as a C pointer for the same reason as in
 * tools/hw_rust_core_ex_driver_b.c: TI allocates argument registers
 * positionally while this backend allocates by class (pointer -> XAR4/XAR5,
 * i16 -> AL/AH), so an `unsigned long` declaration silently swapped ptr/len. */
extern unsigned core_ex_iter_slice2(const unsigned *logical_byte_ptr,
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
    HW_CORE_RESULT[0] = core_ex_iter_slice2(logical_ptr, 4);
    HW_CORE_RESULT[1] = 0xB3;
    hw_done();
    return 0;
}
