/* Core exercise group C (safe indexing): get/get_mut/split_at/first/last
 * over a constant slice.  The in-bounds [] accesses are provably safe, so
 * no panic machinery is pulled; the OOB path is exercised through get(). */
extern unsigned core_ex_index(void);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result")
volatile unsigned HW_CORE_RESULT[2];

unsigned main(void) {
    HW_CORE_RESULT[0] = core_ex_index();
    HW_CORE_RESULT[1] = 0xB3;
    hw_done();
    return 0;
}
