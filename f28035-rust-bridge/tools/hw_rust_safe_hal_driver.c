/* TI C only supplies the register readback and one pre-set of GPIO34; all
 * GPIO sequencing (take, output::<34>, set_low) lives in the Safe HAL,
 * compiled straight to a C28x object by the patched rustc. */
extern void rust_safe_gpio34_low(void);
extern unsigned rust_safe_gpio_probe(void);
extern void hw_done(void);

#pragma DATA_SECTION(HW_RUST_RESULT, ".hw_result")
volatile unsigned HW_RUST_RESULT[11];

/* F28035 GPIO bank B word addresses (same table as the Safe HAL PAC). */
#define GPBMUX1   (*(volatile unsigned *)0x6F96)
#define GPBDIR    (*(volatile unsigned *)0x6F9A)
#define GPBQSEL1  (*(volatile unsigned *)0x6F94)
#define GPBPUD    (*(volatile unsigned *)0x6F9C)
#define GPBDAT    (*(volatile unsigned *)0x6FC8)
#define GPBSET    (*(volatile unsigned *)0x6FCA)
#define GPIO34_BIT 0x0004u

unsigned main(void) {
    unsigned mux_before = GPBMUX1;
    unsigned dir_before = GPBDIR;
    unsigned dat_before;
    /* Pre-set the pin high in C so the HAL's set_low has a visible effect:
     * GPBDAT bit 2 must fall as a result of the Rust call. */
    GPBSET = GPIO34_BIT;
    dat_before = GPBDAT;
    HW_RUST_RESULT[6] = rust_safe_gpio_probe();
    HW_RUST_RESULT[7] = GPBDIR;
    HW_RUST_RESULT[8] = GPBQSEL1;
    HW_RUST_RESULT[9] = GPBPUD;
    HW_RUST_RESULT[10] = GPBDAT;
    rust_safe_gpio34_low();
    HW_RUST_RESULT[0] = mux_before;
    HW_RUST_RESULT[1] = GPBMUX1;
    HW_RUST_RESULT[2] = dir_before;
    HW_RUST_RESULT[3] = GPBDIR;
    HW_RUST_RESULT[4] = GPBDAT;
    HW_RUST_RESULT[5] = 0xB2;
    (void)dat_before;
    hw_done();
    return 0;
}
