/* Driver for the layered B-1 probe.  All inputs come from here so the Rust
 * entries cannot be constant-folded; results land in HW_LAYER_RESULT.
 *
 * Expected:
 *   [0]  lp_echo(0x1234)      = 0x1234
 *   [1]  lp_cmp_eq(5,5)       = 1
 *   [2]  lp_cmp_eq(5,6)       = 0
 *   [3]  lp_if_zero(0)        = 23
 *   [4]  lp_if_zero(7)        = 40
 *   [5]  lp_mode(0,20)        = 23
 *   [6]  lp_mode(1,20)        = 40
 *   [7]  lp_mode(2,20)        = 19
 *   [8]  lp_sum(data,4)       = 20
 *   [9]  lp_byte_stack(0x77)  = 0x5A77
 *   [10] lp_byte_ptr(bytes)   = 0x33
 *   [11] lp_word_ptr(data)    = 2
 *   [12] marker               = 0x1234
 */
extern unsigned lp_echo(unsigned a);
extern unsigned lp_cmp_eq(unsigned a, unsigned b);
extern unsigned lp_if_zero(unsigned a);
extern unsigned lp_mode(unsigned tag, unsigned v);
extern unsigned lp_sum(const unsigned *ptr, unsigned len);
extern unsigned lp_byte_stack(unsigned x);
extern unsigned lp_byte_ptr(const unsigned char *p);
extern unsigned lp_word_ptr(const unsigned *p);
extern void hw_done(void);

#pragma DATA_SECTION(HW_LAYER_RESULT, ".hw_result")
volatile unsigned HW_LAYER_RESULT[16];

#pragma DATA_SECTION(HW_LAYER_DATA, ".hw_result")
volatile unsigned HW_LAYER_DATA[4];

#pragma DATA_SECTION(HW_LAYER_BYTES, ".hw_result")
volatile unsigned char HW_LAYER_BYTES[4];

unsigned main(void) {
    const unsigned *wptr;
    const unsigned char *bptr;

    HW_LAYER_DATA[0] = 2;
    HW_LAYER_DATA[1] = 4;
    HW_LAYER_DATA[2] = 6;
    HW_LAYER_DATA[3] = 8;
    /* TI C pointers are word addresses; Rust pointers are logical bytes. */
    wptr = (const unsigned *)(((unsigned long)HW_LAYER_DATA) * 2ul);

    HW_LAYER_BYTES[0] = 0x33;
    HW_LAYER_BYTES[1] = 0x44;
    bptr = (const unsigned char *)(((unsigned long)HW_LAYER_BYTES) * 2ul);

    HW_LAYER_RESULT[0] = lp_echo(0x1234);
    HW_LAYER_RESULT[1] = lp_cmp_eq(5, 5);
    HW_LAYER_RESULT[2] = lp_cmp_eq(5, 6);
    HW_LAYER_RESULT[3] = lp_if_zero(0);
    HW_LAYER_RESULT[4] = lp_if_zero(7);
    HW_LAYER_RESULT[5] = lp_mode(0, 20);
    HW_LAYER_RESULT[6] = lp_mode(1, 20);
    HW_LAYER_RESULT[7] = lp_mode(2, 20);
    HW_LAYER_RESULT[8] = lp_sum(wptr, 4);
    HW_LAYER_RESULT[9] = lp_byte_stack(0x77);
    HW_LAYER_RESULT[10] = lp_byte_ptr(bptr);
    HW_LAYER_RESULT[11] = lp_word_ptr(wptr);
    HW_LAYER_RESULT[12] = 0x1234;
    hw_done();
    return 0;
}
