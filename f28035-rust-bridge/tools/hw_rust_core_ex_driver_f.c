/* Core exercise group F: u32/i32 boundary + variable-shift regression.
 * Operands come from TI C so the Rust bodies cannot be constant-folded.
 * The expected sequence directly regresses the LSL ACC,T defect: a 32-bit
 * variable left shift by 16..31 must move the value (LSLL uses T(4:0)); the
 * old LSL ACC,T consumed only T(3:0) and left a shift of 16..31 in place.
 * See the host test module in backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs. */
extern unsigned bnd_shl(unsigned a, unsigned n);
extern unsigned bnd_shl_lo(unsigned a, unsigned n);
extern unsigned bnd_shr(unsigned a, unsigned n);
extern unsigned bnd_u32_addhi(unsigned a, unsigned b);
extern unsigned bnd_u32_subhi(unsigned a, unsigned b);
extern unsigned bnd_u32_cmp(unsigned a, unsigned b);
extern unsigned bnd_i16_cmp(unsigned a, unsigned b);
extern void hw_done(void);

#pragma DATA_SECTION(HW_CORE_RESULT, ".hw_result")
volatile unsigned HW_CORE_RESULT[16];

unsigned main(void) {
    HW_CORE_RESULT[0]  = bnd_shl(0x1234, 16);       /* 0x1234  (bug: 0x0000) */
    HW_CORE_RESULT[1]  = bnd_shl(0x1234, 17);       /* 0x2468  (bug: 0x0000) */
    HW_CORE_RESULT[2]  = bnd_shl(0xFFFF, 31);       /* 0x8000  (bug: 0x0000) */
    HW_CORE_RESULT[3]  = bnd_shl_lo(0x1234, 8);     /* 0x3400 */
    HW_CORE_RESULT[4]  = bnd_shr(0x1234, 16);       /* 0x1234 */
    HW_CORE_RESULT[5]  = bnd_shr(0x1234, 17);       /* 0x091A */
    HW_CORE_RESULT[6]  = bnd_shr(0x1234, 31);       /* 0x0000 */
    HW_CORE_RESULT[7]  = bnd_u32_addhi(0x1234, 0xFFFF); /* 0x1235 */
    HW_CORE_RESULT[8]  = bnd_u32_addhi(0xFFFF, 0xFFFF); /* 0x0000 (wrap) */
    HW_CORE_RESULT[9]  = bnd_u32_subhi(0x1234, 0x0001); /* 0x1233 */
    HW_CORE_RESULT[10] = bnd_u32_cmp(1, 1);         /* 1 */
    HW_CORE_RESULT[11] = bnd_u32_cmp(1, 2);         /* 0 */
    HW_CORE_RESULT[12] = bnd_i16_cmp(0xFFFF, 0);    /* 1  (-1 < 0) */
    HW_CORE_RESULT[13] = bnd_i16_cmp(0, 0xFFFF);    /* 0  (0 < -1 false) */
    HW_CORE_RESULT[14] = 0xB4;
    HW_CORE_RESULT[15] = 0;
    hw_done();
    return 0;
}
