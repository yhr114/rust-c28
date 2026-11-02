/* Core exercise group D (arithmetic and bit tricks): wrapping/overflowing
 * ops, checked_div, rotates, leading/trailing zeros, count_ones, pow,
 * Wrapping<T> operators.  Pulls the c28x-di64-helpers __muldi3 through
 * the widened checked-multiply path, so it also exercises that helper
 * object on hardware. */
extern unsigned core_ex_arith(void);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result")
volatile unsigned HW_CORE_RESULT[2];

unsigned main(void) {
    HW_CORE_RESULT[0] = core_ex_arith();
    HW_CORE_RESULT[1] = 0xB3;
    hw_done();
    return 0;
}
