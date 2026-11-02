/* TI C driver for the B-1 static-address sample.
 *
 * The Rust side exports statics that hold addresses; TI C declares them with
 * C pointer types.  Every Rust-facing pointer carries a LOGICAL BYTE address,
 * so the C side only needs to dereference/call them; no address arithmetic.
 *
 * All Rust calls happen BEFORE the result stores: the .hw_result section sits
 * close to the stack and callee frames were observed clobbering early stores.
 */
extern unsigned short use_table(unsigned short x);
extern unsigned short use_ref(unsigned short x);
extern unsigned short use_data_ptr(void);
extern unsigned short use_data_ref(void);
extern unsigned short fn_a(unsigned short x);
extern unsigned short fn_b(unsigned short x);
extern void hw_done(void);

/* Rust statics: a table of function pointers and a pointer with an addend. */
extern unsigned short (*const TABLE[2])(unsigned short);
extern unsigned short *const DATA_PTR;

#pragma DATA_SECTION(HW_STATIC_RESULT, ".hw_result")
volatile unsigned long HW_STATIC_RESULT[8];

unsigned main(void) {
    unsigned long table_sum;
    unsigned long ref_sum;
    unsigned long data_value;
    unsigned long direct_call;

    /* 1. call through the static table from Rust */
    table_sum = use_table(5);              /* 6 + 10 = 16 */

    /* 2. call through a static &TABLE reference from Rust */
    ref_sum = use_ref(4);                  /* 5 + 8 = 13 */

    /* 3. read through a static pointer with a nonzero addend */
    data_value = use_data_ptr();           /* DATA[1] = 11 */

    /* 4. call through the same table from TI C.  Rust pointers are LOGICAL
     *    BYTE addresses (ABI L1-1) while TI C function pointers/data pointers
     *    are WORD addresses, so the value loaded from the table must be
     *    halved before the C side uses it -- the mirror image of the
     *    `* 2ul` the ABI sample applies when handing a C pointer to Rust. */
    direct_call = (unsigned long)((unsigned short (*)(unsigned short))
                      ((unsigned long)TABLE[0] >> 1))(3)
                + (unsigned long)((unsigned short (*)(unsigned short))
                      ((unsigned long)TABLE[1] >> 1))(4);

    /* 5. a direct Rust->Rust call as the control (no table involved) */
    HW_STATIC_RESULT[0] = table_sum;
    HW_STATIC_RESULT[1] = ref_sum;
    HW_STATIC_RESULT[2] = data_value;
    HW_STATIC_RESULT[3] = direct_call;     /* 4 + 8 = 12 */
    HW_STATIC_RESULT[4] = fn_a(20);        /* 21 */
    HW_STATIC_RESULT[5] = fn_b(20);        /* 40 */
    /* C reads through the relocated static pointer: the field holds a logical
     * byte address, so halve it for a C word-address dereference.  A dropped
     * ABS32 relocation would make this a read of address 0. */
    HW_STATIC_RESULT[6] = *(unsigned short *)((unsigned long)DATA_PTR >> 1);
    HW_STATIC_RESULT[7] = 0x5C;
    hw_done();
    return 0;
}
