/* Hardware probe driver for option-deref-probe.rs.
   Calls the four probe variants plus probe_all, stores results in
   HW_PROBE_RESULT, then signals completion via hw_done. */

extern unsigned probe_is_some_temp(void);
extern unsigned probe_deref_rodata(void);
extern unsigned probe_deref_stack(void);
extern unsigned probe_all(void);
extern void hw_done(void);

#pragma DATA_SECTION(HW_PROBE_RESULT, ".hw_result")
volatile unsigned HW_PROBE_RESULT[5];

unsigned main(void) {
    HW_PROBE_RESULT[0] = probe_is_some_temp();
    HW_PROBE_RESULT[1] = probe_deref_rodata();
    HW_PROBE_RESULT[2] = probe_deref_stack();
    HW_PROBE_RESULT[3] = probe_all();
    HW_PROBE_RESULT[4] = 0x5A5A;
    hw_done();
    return 0;
}
