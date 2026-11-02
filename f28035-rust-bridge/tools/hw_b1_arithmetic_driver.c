extern unsigned long rust_div_u32(unsigned long, unsigned long);
extern unsigned long rust_rem_u32(unsigned long, unsigned long);
extern long rust_div_i32(long, long);
extern long rust_rem_i32(long, long);
extern unsigned long rust_add_f32(unsigned long, unsigned long);
extern unsigned long rust_sub_f32(unsigned long, unsigned long);
extern unsigned long rust_mul_f32(unsigned long, unsigned long);
extern unsigned long rust_div_f32(unsigned long, unsigned long);
extern unsigned long rust_call_four(const unsigned short *, unsigned long);
extern void hw_done(void);

#pragma DATA_SECTION(HW_ARITH_RESULT, ".hw_result")
volatile unsigned long HW_ARITH_RESULT[64];
const unsigned short CALL_DATA = 7;
unsigned long check_four(const unsigned short *p, unsigned long count,
                         unsigned long size, const unsigned short *location) {
    /* Incoming Rust pointers contain logical byte addresses. */
    const unsigned short *word_p = (const unsigned short *)((unsigned long)p >> 1);
    const unsigned short *word_location = (const unsigned short *)((unsigned long)location >> 1);
    return count * 17ul + size * 257ul + *word_p + *word_location;
}

unsigned main(void) {
    unsigned i = 0;
    HW_ARITH_RESULT[i++] = rust_div_u32(23ul, 3ul);
    HW_ARITH_RESULT[i++] = rust_rem_u32(23ul, 3ul);
    HW_ARITH_RESULT[i++] = rust_div_u32(0xfffffffful, 0x10001ul);
    HW_ARITH_RESULT[i++] = rust_rem_u32(0xfffffffful, 0x10001ul);
    HW_ARITH_RESULT[i++] = rust_div_u32(0x80000000ul, 7ul);
    HW_ARITH_RESULT[i++] = rust_rem_u32(0x80000000ul, 7ul);
    HW_ARITH_RESULT[i++] = rust_div_u32(3ul, 9ul);
    HW_ARITH_RESULT[i++] = rust_rem_u32(3ul, 9ul);
    HW_ARITH_RESULT[i++] = rust_div_u32(0ul, 9ul);
    HW_ARITH_RESULT[i++] = rust_rem_u32(0ul, 9ul);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_div_i32(-23l, 3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_rem_i32(-23l, 3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_div_i32(23l, -3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_rem_i32(23l, -3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_div_i32(-23l, -3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_rem_i32(-23l, -3l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_div_i32((-2147483647l - 1l), 1l);
    HW_ARITH_RESULT[i++] = (unsigned long)rust_rem_i32((-2147483647l - 1l), 7l);
    HW_ARITH_RESULT[i++] = rust_add_f32(0x3fa00000ul, 0x40200000ul); /* 1.25+2.5 */
    HW_ARITH_RESULT[i++] = rust_sub_f32(0x3fa00000ul, 0x40200000ul);
    HW_ARITH_RESULT[i++] = rust_mul_f32(0xc0000000ul, 0x40400000ul); /* -2*3 */
    HW_ARITH_RESULT[i++] = rust_div_f32(0x40e00000ul, 0x40000000ul); /* 7/2 */
    HW_ARITH_RESULT[i++] = rust_add_f32(0x3f800000ul, 0x33800000ul); /* ties-even */
    HW_ARITH_RESULT[i++] = rust_mul_f32(0x80000000ul, 0x40000000ul); /* -0*2 */
    HW_ARITH_RESULT[i++] = rust_div_f32(0x3f800000ul, 0ul);         /* +inf */
    HW_ARITH_RESULT[i++] = rust_mul_f32(0xff800000ul, 0x40000000ul);
    HW_ARITH_RESULT[i++] = rust_add_f32(1ul, 1ul);                /* subnormal */
    HW_ARITH_RESULT[i++] = rust_div_f32(0x00800000ul, 0x40000000ul);
    HW_ARITH_RESULT[i++] = rust_add_f32(0x7f800000ul, 0xff800000ul); /* NaN */
    HW_ARITH_RESULT[i++] = rust_call_four(
        (const unsigned short *)((unsigned long)&CALL_DATA * 2ul), 5ul);
    HW_ARITH_RESULT[i++] = rust_call_four(
        (const unsigned short *)((unsigned long)&CALL_DATA * 2ul), 0x10001ul);
    HW_ARITH_RESULT[i++] = 0xb1a0ul;
    hw_done();
    return 0;
}
