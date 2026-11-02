extern unsigned short rust_static_data(void);
extern unsigned short rust_static_local(void);
extern unsigned short rust_static_odd(void);
extern void hw_done(void);

/* TI word addresses are doubled only by the Rust object's relocations. */
const unsigned short external_data = 0x1234;
unsigned short external_value(unsigned short value) { return value + 7; }
#pragma DATA_SECTION(HW_STATIC_RESULT, ".hw_result")
volatile unsigned short HW_STATIC_RESULT[3];

unsigned main(void) {
    HW_STATIC_RESULT[0] = rust_static_data();
    HW_STATIC_RESULT[1] = rust_static_local();
    HW_STATIC_RESULT[2] = rust_static_odd();
    hw_done();
    return 0;
}
