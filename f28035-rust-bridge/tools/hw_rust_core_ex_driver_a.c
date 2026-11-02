/* Core exercise group A (cheap core closure): Option/Result combinators,
 * mem, comparisons, closures/fn pointers/recursion, pattern matching.
 * Sized to fit the F28035 program RAM (0x8000-0x9FFF, 4096 words); see
 * run-hw-rustc-direct-core-ex.ps1 for the group split rationale. */
extern unsigned core_ex_option(void);
extern unsigned core_ex_result(void);
extern unsigned core_ex_mem(void);
extern unsigned core_ex_cmp(void);
extern unsigned core_ex_closure(void);
extern unsigned core_ex_pattern(void);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result")
volatile unsigned HW_CORE_RESULT[7];

unsigned main(void) {
    HW_CORE_RESULT[0] = core_ex_option();
    HW_CORE_RESULT[1] = core_ex_result();
    HW_CORE_RESULT[2] = core_ex_mem();
    HW_CORE_RESULT[3] = core_ex_cmp();
    HW_CORE_RESULT[4] = core_ex_closure();
    HW_CORE_RESULT[5] = core_ex_pattern();
    HW_CORE_RESULT[6] = 0xB3;
    hw_done();
    return 0;
}
