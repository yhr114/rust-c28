#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_RXRDY        0x5C2A00UL
#define FAIL_DATA         0x5C2B00UL
#define FAIL_ERR          0x5C2C00UL
#define FAIL_TXFREE       0x5C2D00UL

#define FAIL_TOGGLE_RXRDY 0x5C3200UL
#define FAIL_TOGGLE_DATA  0x5C3300UL
#define FAIL_TOGGLE_ERR   0x5C3400UL

#define FAIL_ENT_RXRDY    0x5B8000UL
#define FAIL_ENT_DATA     0x5B8100UL
#define FAIL_ENT_ERR      0x5B8200UL

#define FAIL_C7_RXRDY     0x5B7800UL
#define FAIL_C7_DATA      0x5B7900UL
#define FAIL_C7_ERR       0x5B7A00UL

#define FAIL_MAT_RXRDY    0x5B7400UL
#define FAIL_MAT_DATA     0x5B7500UL
#define FAIL_MAT_ERR      0x5B7600UL

#define FAIL_C6_RXRDY     0x5B8A00UL
#define FAIL_C6_DATA      0x5B8B00UL
#define FAIL_C6_ERR       0x5B8C00UL

#define FAIL_EXACT_RXRDY  0x5BAA00UL
#define FAIL_EXACT_DATA   0x5BAB00UL
#define FAIL_EXACT_ERR    0x5BAC00UL

#define FAIL_STOP2_RXRDY  0x5B8E00UL
#define FAIL_STOP2_DATA   0x5B8F00UL
#define FAIL_STOP2_ERR    0x5B9000UL

typedef struct {
    unsigned short ch;
    unsigned short txdata;
} sci_vec_t;

typedef struct {
    const unsigned short *patterns;
    unsigned short count;
} sci_pattern_profile_t;

static unsigned short sci_char_mask(unsigned short ch)
{
    if (ch >= 7U) {
        return 0x00FFU;
    }
    return (unsigned short)((1U << (ch + 1U)) - 1U);
}

static void sci_write_sciccr(unsigned short stop2,
                             unsigned short ch,
                             unsigned short parity_en,
                             unsigned short parity)
{
    EALLOW;
    sci_reg_write16(SCI_REG_SCICCR,
                    (unsigned short)(SCICCR_LOOPB_MASK |
                                     ((stop2 != 0U) ? SCICCR_STOP_MASK : 0U) |
                                     ((parity_en != 0U) ? SCICCR_PARITY_EN_MASK : 0U) |
                                     ((parity != 0U) ? SCICCR_PARITY_MASK : 0U) |
                                     (ch & SCICCR_CHAR_MASK)));
    EDIS;
}

static void sci_expect_common(unsigned short phase,
                              unsigned short stop2,
                              unsigned short ch,
                              unsigned short parity,
                              unsigned short txdata,
                              unsigned short idx,
                              unsigned short check_rxwk,
                              unsigned long fail_rxrdy,
                              unsigned long fail_data,
                              unsigned long fail_err)
{
    unsigned short st;
    unsigned short rx;
    unsigned short mask;
    unsigned long tag;

    tag = ((unsigned long)phase << 16) |
          ((unsigned long)stop2 << 13) |
          ((unsigned long)parity << 12) |
          ((unsigned long)ch << 8) |
          (unsigned long)idx;
    mask = sci_char_mask(ch);

    sci_reg_write16(SCI_REG_SCITXBUF, txdata);
    st = sci_case_wait_rxrdy(240000UL);
    if ((st & SCIRXST_RXRDY_MASK) == 0U) {
        test_runtime_fail(fail_rxrdy + tag + (unsigned long)st);
    }
    if ((st & (SCIRXST_PE_MASK | SCIRXST_FE_MASK | SCIRXST_OE_MASK | SCIRXST_RXERR_MASK)) != 0U) {
        test_runtime_fail(fail_err + tag + (unsigned long)st);
    }
    if ((check_rxwk != 0U) && (ch >= 2U) && ((st & SCIRXST_RXWK_MASK) != 0U)) {
        test_runtime_fail(fail_err + 0x80UL + tag + (unsigned long)st);
    }

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != (txdata & mask)) {
        test_runtime_fail(fail_data + tag + (unsigned long)sci_case_rx_byte(rx));
    }
}

static void sci_run_stop2_parity_matrix(unsigned short stop2, unsigned short two_patterns)
{
    unsigned short ch;
    unsigned short parity;

    for (parity = 0U; parity <= 1U; ++parity) {
        for (ch = 0U; ch <= 7U; ++ch) {
            sci_write_sciccr(stop2, ch, 1U, parity);
            sci_expect_common(0U, stop2, ch, parity,
                              (unsigned short)(0x00A5U ^ (unsigned short)(ch << 1) ^ (unsigned short)(parity << 7)),
                              0U, 1U, FAIL_RXRDY, FAIL_DATA, FAIL_ERR);
            if (two_patterns != 0U) {
                sci_expect_common(0U, stop2, ch, parity,
                                  (unsigned short)(0x005AU ^ (unsigned short)(ch << 2) ^ (unsigned short)(parity << 6)),
                                  1U, 1U, FAIL_RXRDY, FAIL_DATA, FAIL_ERR);
            }
        }
    }
}

static void sci_run_stop2_toggle_charlen_matrix(void)
{
    unsigned short stop2;
    unsigned short ch;

    for (stop2 = 0U; stop2 <= 1U; ++stop2) {
        for (ch = 0U; ch <= 7U; ++ch) {
            sci_write_sciccr(stop2, ch, 0U, 0U);
            sci_expect_common(1U, stop2, ch, 0U,
                              (unsigned short)(0x0093U ^ (unsigned short)(stop2 << 6) ^ (unsigned short)(ch << 1)),
                              0U, 1U, FAIL_TOGGLE_RXRDY, FAIL_TOGGLE_DATA, FAIL_TOGGLE_ERR);
            sci_expect_common(1U, stop2, ch, 0U,
                              (unsigned short)(0x005CU ^ (unsigned short)(stop2 << 5) ^ (unsigned short)(ch << 2)),
                              1U, 1U, FAIL_TOGGLE_RXRDY, FAIL_TOGGLE_DATA, FAIL_TOGGLE_ERR);
        }
    }
}

static void run_stop2_char567_entropy(void)
{
    static const unsigned short patterns[] = {
        0x00U, 0x01U, 0x03U, 0x07U, 0x0FU, 0x1FU, 0x3FU, 0x7FU,
        0x80U, 0x81U, 0x83U, 0x87U, 0x8FU, 0x9FU, 0xAFU, 0xBFU,
        0xC0U, 0xC1U, 0xC3U, 0xC7U, 0xCFU, 0xD7U, 0xDBU, 0xE7U,
        0xEDU, 0xF1U, 0xF3U, 0xF7U, 0xFBU, 0xFDU, 0xFEU, 0xFFU,
        0x96U, 0x69U, 0x5AU, 0xA5U, 0x3CU, 0xC3U, 0x66U, 0x99U
    };
    static const unsigned short chars[] = {5U, 6U, 7U};
    unsigned short c;
    unsigned short parity;
    unsigned short i;

    for (c = 0U; c < (unsigned short)(sizeof(chars) / sizeof(chars[0])); ++c) {
        for (parity = 0U; parity <= 1U; ++parity) {
            sci_write_sciccr(1U, chars[c], 1U, parity);
            for (i = 0U; i < (unsigned short)(sizeof(patterns) / sizeof(patterns[0])); ++i) {
                sci_expect_common(2U, 1U, chars[c], parity, patterns[i],
                                  (unsigned short)(i + (parity * 64U) + (c * 128U)),
                                  0U, FAIL_ENT_RXRDY, FAIL_ENT_DATA, FAIL_ENT_ERR);
            }
        }
    }
}

static void run_char7_entropy_residual(void)
{
    static const unsigned short patterns[] = {
        0x00U, 0x01U, 0x03U, 0x07U, 0x0FU, 0x1FU, 0x3FU, 0x7FU,
        0x80U, 0x81U, 0x83U, 0x87U, 0x8FU, 0x9FU, 0xAFU, 0xBFU,
        0xC0U, 0xC1U, 0xC3U, 0xC7U, 0xCFU, 0xD7U, 0xDBU, 0xE7U,
        0xEDU, 0xF1U, 0xF3U, 0xF7U, 0xFBU, 0xFDU, 0xFEU, 0xFFU,
        0x96U, 0x69U, 0x5AU, 0xA5U, 0x3CU, 0xC3U, 0x66U, 0x99U,
        0x0EU, 0x14U, 0x1DU, 0x1EU, 0x24U, 0x28U, 0x33U, 0x3BU,
        0x3EU, 0x46U, 0x48U, 0x49U, 0x4BU, 0x4EU, 0x50U, 0x51U,
        0x53U, 0x54U, 0x56U, 0x58U, 0x59U, 0x5CU, 0x5DU, 0x5EU,
        0x60U, 0x62U, 0x63U, 0x65U, 0x68U, 0x6AU, 0x6BU, 0x6CU,
        0x6FU, 0x70U, 0x74U, 0x75U, 0x76U, 0x78U, 0x79U, 0x7AU,
        0x7CU
    };
    unsigned short parity;
    unsigned short i;

    for (parity = 0U; parity <= 1U; ++parity) {
        sci_write_sciccr(0U, 7U, 1U, parity);
        for (i = 0U; i < (unsigned short)(sizeof(patterns) / sizeof(patterns[0])); ++i) {
            sci_expect_common(3U, 0U, 7U, parity, patterns[i],
                              (unsigned short)(i + (parity * 128U)),
                              0U, FAIL_C7_RXRDY, FAIL_C7_DATA, FAIL_C7_ERR);
        }
    }
}

static void run_parity_entropy_matrix(void)
{
    static const sci_vec_t vecs[] = {
        {5U, 0x00U}, {5U, 0x07U}, {5U, 0x15U}, {5U, 0x1AU}, {5U, 0x23U}, {5U, 0x2CU}, {5U, 0x35U}, {5U, 0x3EU},
        {6U, 0x00U}, {6U, 0x0DU}, {6U, 0x16U}, {6U, 0x1BU}, {6U, 0x25U}, {6U, 0x2AU}, {6U, 0x34U}, {6U, 0x39U},
        {6U, 0x43U}, {6U, 0x4CU}, {6U, 0x55U}, {6U, 0x5AU},
        {7U, 0x00U}, {7U, 0x13U}, {7U, 0x26U}, {7U, 0x39U}, {7U, 0x4CU}, {7U, 0x5FU}, {7U, 0x72U}, {7U, 0x85U},
        {7U, 0x96U}, {7U, 0xA9U}, {7U, 0xBCU}, {7U, 0xCFU}, {7U, 0xE1U}, {7U, 0xF2U}
    };
    unsigned short i;
    unsigned short last_ch;

    last_ch = 0xFFFFU;
    for (i = 0U; i < (unsigned short)(sizeof(vecs) / sizeof(vecs[0])); ++i) {
        if (vecs[i].ch != last_ch) {
            sci_write_sciccr(0U, vecs[i].ch, 1U, 0U);
            last_ch = vecs[i].ch;
        }
        sci_expect_common(4U, 0U, vecs[i].ch, 0U, vecs[i].txdata, i,
                          0U, FAIL_MAT_RXRDY, FAIL_MAT_DATA, FAIL_MAT_ERR);
    }
}

void main(void)
{
    unsigned short ctl2;

    device_sdk_init();
    sci_case_basic_init_no_fifo((unsigned short)(SCICCR_LOOPB_MASK |
                                                 SCICCR_STOP_MASK |
                                                 SCICCR_PARITY_EN_MASK),
                                0U,
                                3U);

    sci_run_stop2_parity_matrix(0U, 0U);
    sci_run_stop2_parity_matrix(1U, 1U);
    sci_run_stop2_toggle_charlen_matrix();
    run_stop2_char567_entropy();
    run_char7_entropy_residual();
    run_parity_entropy_matrix();

    ctl2 = sci_case_wait_txfree(240000UL);
    if ((ctl2 & (SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) !=
        (SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) {
        test_runtime_fail(FAIL_TXFREE + (unsigned long)ctl2);
    }

    test_runtime_pass();
}
