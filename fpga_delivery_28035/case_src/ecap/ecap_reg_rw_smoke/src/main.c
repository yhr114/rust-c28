#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "ecap_reg_rw_smoke only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint32 g_reset_tsctr;
volatile Uint32 g_reset_ctrphs;
volatile Uint32 g_reset_cap1;
volatile Uint32 g_reset_cap2;
volatile Uint32 g_reset_cap3;
volatile Uint32 g_reset_cap4;
volatile Uint16 g_reset_ecctl1;
volatile Uint16 g_reset_ecctl2;
volatile Uint16 g_reset_eceint;
volatile Uint16 g_reset_ecflg;

volatile Uint32 g_ctrphs_readback_5555;
volatile Uint32 g_ctrphs_readback_aaaa;
volatile Uint32 g_ctrphs_readback_zero;
volatile Uint32 g_tsctr_readback_5555;
volatile Uint32 g_tsctr_readback_aaaa;
volatile Uint32 g_cap1_readback_5555;
volatile Uint32 g_cap1_readback_aaaa;
volatile Uint32 g_cap2_readback_5555;
volatile Uint32 g_cap2_readback_aaaa;
volatile Uint32 g_cap3_readback_5555;
volatile Uint32 g_cap3_readback_aaaa;
volatile Uint32 g_cap4_readback_5555;
volatile Uint32 g_cap4_readback_aaaa;
volatile Uint16 g_ecclr_readback;
volatile Uint16 g_ecfrc_readback;
volatile Uint16 g_ecctl1_readback_5555;
volatile Uint16 g_ecctl1_readback_aaaa;
volatile Uint16 g_eceint_readback_5555;
volatile Uint16 g_eceint_readback_aaaa;

static void ecap_init_case(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.ECAP1ENCLK = 1U;
    EDIS;
}

static void capture_reset_snapshot(void)
{
    g_reset_tsctr = ECap1Regs.TSCTR;
    g_reset_ctrphs = ECap1Regs.CTRPHS;
    g_reset_cap1 = ECap1Regs.CAP1;
    g_reset_cap2 = ECap1Regs.CAP2;
    g_reset_cap3 = ECap1Regs.CAP3;
    g_reset_cap4 = ECap1Regs.CAP4;
    g_reset_ecctl1 = ECap1Regs.ECCTL1.all;
    g_reset_ecctl2 = ECap1Regs.ECCTL2.all;
    g_reset_eceint = ECap1Regs.ECEINT.all;
    g_reset_ecflg = ECap1Regs.ECFLG.all;
}

static void prepare_rw_phase(void)
{
    /*
     * Reset checking must happen before this point. From here on we are free
     * to clear sticky state and drive registers into a quiet baseline for
     * mask-based RW verification.
     */
    ECap1Regs.ECEINT.all = 0U;
    ECap1Regs.ECCLR.all = 0x00FFU;
    ECap1Regs.ECCTL1.all = 0U;
    ECap1Regs.ECCTL2.all = ECAP_REG_RW_RESET_ECCTL2;
    ECap1Regs.TSCTR = 0UL;
    ECap1Regs.CTRPHS = 0UL;
    ECap1Regs.CAP1 = 0UL;
    ECap1Regs.CAP2 = 0UL;
    ECap1Regs.CAP3 = 0UL;
    ECap1Regs.CAP4 = 0UL;
}

static void check_reset_values(void)
{
    if (g_reset_tsctr != ECAP_REG_RW_RESET_TSCTR) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_TSCTR);
    }
    if (g_reset_ctrphs != ECAP_REG_RW_RESET_CTRPHS) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_CTRPHS);
    }
    if (g_reset_cap1 != ECAP_REG_RW_RESET_CAP1) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_CAP1);
    }
    if (g_reset_cap2 != ECAP_REG_RW_RESET_CAP2) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_CAP2);
    }
    if (g_reset_cap3 != ECAP_REG_RW_RESET_CAP3) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_CAP3);
    }
    if (g_reset_cap4 != ECAP_REG_RW_RESET_CAP4) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_CAP4);
    }
    if (g_reset_ecctl1 != ECAP_REG_RW_RESET_ECCTL1) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_ECCTL1);
    }
    if (g_reset_ecctl2 != ECAP_REG_RW_RESET_ECCTL2) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_ECCTL2);
    }
    if (g_reset_eceint != ECAP_REG_RW_RESET_ECEINT) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_ECEINT);
    }
    if (g_reset_ecflg != ECAP_REG_RW_RESET_ECFLG) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RESET_ECFLG);
    }
}

static void check_ctrphs_rw_masked(void)
{
    ECap1Regs.CTRPHS = ECAP_REG_RW_WRITE_5555_32;
    g_ctrphs_readback_5555 = ECap1Regs.CTRPHS;
    if (g_ctrphs_readback_5555 !=
        (ECAP_REG_RW_WRITE_5555_32 & ECAP_REG_RW_MASK_CTRPHS)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CTRPHS_5555);
    }

    ECap1Regs.CTRPHS = ECAP_REG_RW_WRITE_AAAA_32;
    g_ctrphs_readback_aaaa = ECap1Regs.CTRPHS;
    if (g_ctrphs_readback_aaaa !=
        (ECAP_REG_RW_WRITE_AAAA_32 & ECAP_REG_RW_MASK_CTRPHS)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CTRPHS_AAAA);
    }

    /* Complete the odd-bit 1->0 transition after the 0xAAAAAAAA pattern. */
    ECap1Regs.CTRPHS = ECAP_REG_RW_WRITE_ZERO_32;
    g_ctrphs_readback_zero = ECap1Regs.CTRPHS;
    if (g_ctrphs_readback_zero !=
        (ECAP_REG_RW_WRITE_ZERO_32 & ECAP_REG_RW_MASK_CTRPHS)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CTRPHS_ZERO);
    }
}

static void check_ecctl1_rw_masked(void)
{
    ECap1Regs.ECCTL1.all = ECAP_REG_RW_WRITE_5555_16;
    g_ecctl1_readback_5555 = ECap1Regs.ECCTL1.all;
    if (g_ecctl1_readback_5555 !=
        (ECAP_REG_RW_WRITE_5555_16 & ECAP_REG_RW_MASK_ECCTL1)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_ECCTL1_5555);
    }

    ECap1Regs.ECCTL1.all = ECAP_REG_RW_WRITE_AAAA_16;
    g_ecctl1_readback_aaaa = ECap1Regs.ECCTL1.all;
    if (g_ecctl1_readback_aaaa !=
        (ECAP_REG_RW_WRITE_AAAA_16 & ECAP_REG_RW_MASK_ECCTL1)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_ECCTL1_AAAA);
    }
}

static void check_data_32_rw_masks(void)
{
    ECap1Regs.TSCTR = ECAP_REG_RW_WRITE_5555_32;
    g_tsctr_readback_5555 = ECap1Regs.TSCTR;
    if (g_tsctr_readback_5555 != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_TSCTR_5555);
    }
    ECap1Regs.TSCTR = ECAP_REG_RW_WRITE_AAAA_32;
    g_tsctr_readback_aaaa = ECap1Regs.TSCTR;
    if (g_tsctr_readback_aaaa != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_TSCTR_AAAA);
    }

    ECap1Regs.CAP1 = ECAP_REG_RW_WRITE_5555_32;
    g_cap1_readback_5555 = ECap1Regs.CAP1;
    if (g_cap1_readback_5555 != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP1_5555);
    }
    ECap1Regs.CAP1 = ECAP_REG_RW_WRITE_AAAA_32;
    g_cap1_readback_aaaa = ECap1Regs.CAP1;
    if (g_cap1_readback_aaaa != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP1_AAAA);
    }

    ECap1Regs.CAP2 = ECAP_REG_RW_WRITE_5555_32;
    g_cap2_readback_5555 = ECap1Regs.CAP2;
    if (g_cap2_readback_5555 != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP2_5555);
    }
    ECap1Regs.CAP2 = ECAP_REG_RW_WRITE_AAAA_32;
    g_cap2_readback_aaaa = ECap1Regs.CAP2;
    if (g_cap2_readback_aaaa != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP2_AAAA);
    }

    ECap1Regs.CAP3 = ECAP_REG_RW_WRITE_5555_32;
    g_cap3_readback_5555 = ECap1Regs.CAP3;
    if (g_cap3_readback_5555 != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP3_5555);
    }
    ECap1Regs.CAP3 = ECAP_REG_RW_WRITE_AAAA_32;
    g_cap3_readback_aaaa = ECap1Regs.CAP3;
    if (g_cap3_readback_aaaa != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP3_AAAA);
    }

    ECap1Regs.CAP4 = ECAP_REG_RW_WRITE_5555_32;
    g_cap4_readback_5555 = ECap1Regs.CAP4;
    if (g_cap4_readback_5555 != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP4_5555);
    }
    ECap1Regs.CAP4 = ECAP_REG_RW_WRITE_AAAA_32;
    g_cap4_readback_aaaa = ECap1Regs.CAP4;
    if (g_cap4_readback_aaaa != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_CAP4_AAAA);
    }
}

static void check_halfword_rw(volatile Uint32 *reg,
                              Uint16 lower_fail,
                              Uint16 upper_fail)
{
    volatile Uint16 *reg_words = (volatile Uint16 *)reg;

    *reg = ECAP_REG_RW_WRITE_AAAA_32;
    reg_words[0] = ECAP_REG_RW_WRITE_5555_16;
    if (*reg != 0xAAAA5555UL) {
        test_runtime_fail(lower_fail);
    }
    reg_words[1] = ECAP_REG_RW_WRITE_5555_16;
    if (*reg != ECAP_REG_RW_WRITE_5555_32) {
        test_runtime_fail(upper_fail);
    }

    reg_words[0] = ECAP_REG_RW_WRITE_AAAA_16;
    if (*reg != 0x5555AAAAUL) {
        test_runtime_fail(lower_fail);
    }
    reg_words[1] = ECAP_REG_RW_WRITE_AAAA_16;
    if (*reg != ECAP_REG_RW_WRITE_AAAA_32) {
        test_runtime_fail(upper_fail);
    }

    *reg = ECAP_REG_RW_WRITE_ZERO_32;
}

static void check_data_32_halfword_access(void)
{
    check_halfword_rw(&ECap1Regs.TSCTR,
                      ECAP_REG_RW_FAIL_HALF_TSCTR_LOW,
                      ECAP_REG_RW_FAIL_HALF_TSCTR_HIGH);
    check_halfword_rw(&ECap1Regs.CTRPHS,
                      ECAP_REG_RW_FAIL_HALF_CTRPHS_LOW,
                      ECAP_REG_RW_FAIL_HALF_CTRPHS_HIGH);
    check_halfword_rw(&ECap1Regs.CAP1,
                      ECAP_REG_RW_FAIL_HALF_CAP1_LOW,
                      ECAP_REG_RW_FAIL_HALF_CAP1_HIGH);
    check_halfword_rw(&ECap1Regs.CAP2,
                      ECAP_REG_RW_FAIL_HALF_CAP2_LOW,
                      ECAP_REG_RW_FAIL_HALF_CAP2_HIGH);
    check_halfword_rw(&ECap1Regs.CAP3,
                      ECAP_REG_RW_FAIL_HALF_CAP3_LOW,
                      ECAP_REG_RW_FAIL_HALF_CAP3_HIGH);
    check_halfword_rw(&ECap1Regs.CAP4,
                      ECAP_REG_RW_FAIL_HALF_CAP4_LOW,
                      ECAP_REG_RW_FAIL_HALF_CAP4_HIGH);
}

static void check_action_register_reads_zero(void)
{
    g_ecclr_readback = ECap1Regs.ECCLR.all;
    g_ecfrc_readback = ECap1Regs.ECFRC.all;

    if (g_ecclr_readback != 0U) {
        test_runtime_fail(ECAP_REG_RW_FAIL_READ_ECCLR);
    }
    if (g_ecfrc_readback != 0U) {
        test_runtime_fail(ECAP_REG_RW_FAIL_READ_ECFRC);
    }
}

static void check_eceint_rw_masked(void)
{
    ECap1Regs.ECEINT.all = ECAP_REG_RW_WRITE_5555_16;
    g_eceint_readback_5555 = ECap1Regs.ECEINT.all;
    if (g_eceint_readback_5555 !=
        (ECAP_REG_RW_WRITE_5555_16 & ECAP_REG_RW_MASK_ECEINT)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_ECEINT_5555);
    }

    ECap1Regs.ECEINT.all = ECAP_REG_RW_WRITE_AAAA_16;
    g_eceint_readback_aaaa = ECap1Regs.ECEINT.all;
    if (g_eceint_readback_aaaa !=
        (ECAP_REG_RW_WRITE_AAAA_16 & ECAP_REG_RW_MASK_ECEINT)) {
        test_runtime_fail(ECAP_REG_RW_FAIL_RW_ECEINT_AAAA);
    }
}

void main(void)
{
    board_demo_init();
    ecap_init_case();
    capture_reset_snapshot();
    check_reset_values();
    prepare_rw_phase();
    check_ctrphs_rw_masked();
    check_data_32_rw_masks();
    check_data_32_halfword_access();
    check_action_register_reads_zero();
    check_ecctl1_rw_masked();
    check_eceint_rw_masked();
    test_runtime_pass();
}
