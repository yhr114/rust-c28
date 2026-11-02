/* Core exercise group E: boolean-comparison regression.
 * All operands come from TI C so the Rust bodies cannot be constant-folded;
 * the expected sequence verifies ==, <, byte-lane compare, compare-with-1,
 * Option tag probes, !bool and unwrap_or on the C28x backend. */
extern unsigned beq(unsigned a, unsigned b);
extern unsigned blt(unsigned a, unsigned b);
extern unsigned beq8(unsigned a, unsigned b);
extern unsigned beq1(unsigned a);
extern unsigned some_of(unsigned tag);
extern unsigned none_of(unsigned tag);
extern unsigned unwrap_of(unsigned tag);
extern unsigned not_of(unsigned tag);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result")
volatile unsigned HW_CORE_RESULT[16];

unsigned main(void) {
    HW_CORE_RESULT[0] = beq(3, 3);          /* 1 */
    HW_CORE_RESULT[1] = beq(3, 4);          /* 0 */
    HW_CORE_RESULT[2] = blt(2, 5);          /* 1 */
    HW_CORE_RESULT[3] = blt(5, 2);          /* 0 */
    HW_CORE_RESULT[4] = beq8(0x107, 0x207); /* 1, low bytes 7 == 7 */
    HW_CORE_RESULT[5] = beq8(0x107, 0x208); /* 0 */
    HW_CORE_RESULT[6] = beq1(1);            /* 1 */
    HW_CORE_RESULT[7] = beq1(2);            /* 0 */
    HW_CORE_RESULT[8] = some_of(1);         /* 1 */
    HW_CORE_RESULT[9] = some_of(0);         /* 0 */
    HW_CORE_RESULT[10] = none_of(0);        /* 1 */
    HW_CORE_RESULT[11] = none_of(1);        /* 0 */
    HW_CORE_RESULT[12] = unwrap_of(1);      /* 5 */
    HW_CORE_RESULT[13] = unwrap_of(0);      /* 9 */
    HW_CORE_RESULT[14] = not_of(0);         /* 0 */
    HW_CORE_RESULT[15] = 0xB3;
    hw_done();
    return 0;
}
