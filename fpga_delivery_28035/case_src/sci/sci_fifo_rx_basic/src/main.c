#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_INIT_TXFIFO 0x5801U
#define FAIL_INIT_RXFIFO 0x5802U
#define FAIL_INIT_CTRL   0x5803U
#define FAIL_LEVEL_RX4   0x5810U
#define FAIL_LEVEL_RX3   0x5811U
#define FAIL_LEVEL_BURST0 0x5812U
#define FAIL_LEVEL_BURST1 0x5813U
#define FAIL_DATA        0x585010UL
#define FAIL_NO_INT      0x587001UL
#define FAIL_NO_LVL      0x587002UL
#define FAIL_RXTH        0x5A0001UL
#define FAIL_TXTH        0x5A0003UL
#define FAIL_INT_SET1    0x5AB001UL
#define FAIL_INT_CLR     0x5AB002UL
#define FAIL_INT_SET2    0x5AB003UL
#define FAIL_DRAIN0      0x5AB004UL
#define FAIL_DRAIN1      0x5AB005UL

typedef struct {
    unsigned short value;
} sci_fifo_vec_t;

volatile unsigned short g_sci_fifo_stage;
volatile unsigned short g_sci_fifo_expected_level;
volatile unsigned short g_sci_fifo_ffrx_snapshot;
volatile unsigned short g_sci_fifo_fftx_snapshot;

static void sci_fifo_capture(unsigned short stage, unsigned short expected_level,
                             unsigned short ffrx)
{
    g_sci_fifo_stage = stage;
    g_sci_fifo_expected_level = expected_level;
    g_sci_fifo_ffrx_snapshot = ffrx;
    g_sci_fifo_fftx_snapshot = sci_reg_read16(SCI_REG_SCIFFTX);
}

static void sci_fifo_reinit(unsigned short rxffil)
{
    unsigned short rd;

    sci_case_basic_init_fifo_loopback(0U, 3U, rxffil, 0U);

    /* Generate explicit FIFO reset edges on every reinitialization. */
    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK));
    sci_reg_write16(SCI_REG_SCIFFRX,
                    (unsigned short)(rxffil & SCIFFRX_FFIL_MASK));
    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK |
                                     SCIFFTX_FFRSTN_MASK));
    sci_reg_write16(SCI_REG_SCIFFRX,
                    (unsigned short)(SCIFFRX_FFRSTN_MASK |
                                     (rxffil & SCIFFRX_FFIL_MASK)));
    sci_case_delay(64UL);

    rd = sci_reg_read16(SCI_REG_SCIFFTX);
    if ((rd & (SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFENA_MASK | SCIFFTX_FFRSTN_MASK)) !=
        (SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFENA_MASK | SCIFFTX_FFRSTN_MASK)) {
        sci_fifo_capture(0U, 0U, sci_reg_read16(SCI_REG_SCIFFRX));
        test_runtime_fail(FAIL_INIT_TXFIFO);
    }

    rd = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((rd & (SCIFFRX_FFRSTN_MASK | SCIFFRX_FFIL_MASK)) !=
        (unsigned short)(SCIFFRX_FFRSTN_MASK | (rxffil & SCIFFRX_FFIL_MASK))) {
        sci_fifo_capture(0U, rxffil, rd);
        test_runtime_fail(FAIL_INIT_RXFIFO);
    }

    rd = sci_reg_read16(SCI_REG_SCICCR);
    if ((rd & SCICCR_LOOPB_MASK) == 0U) {
        sci_fifo_capture(0U, rxffil, sci_reg_read16(SCI_REG_SCIFFRX));
        test_runtime_fail(FAIL_INIT_CTRL);
    }
}

static void sci_fifo_check_byte(unsigned short expected, unsigned short tag)
{
    unsigned short rx;

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != expected) {
        test_runtime_fail(FAIL_DATA + ((unsigned long)tag << 8) +
                          (unsigned long)sci_case_rx_byte(rx));
    }
}

static void sci_fifo_write_and_check(const sci_fifo_vec_t *vecs,
                                     unsigned short count,
                                     unsigned short tag_base,
                                     unsigned short stage,
                                     unsigned short level_fail_code,
                                     unsigned long timeout)
{
    unsigned short i;
    unsigned short ffrx;

    for (i = 0U; i < count; ++i) {
        sci_reg_write16(SCI_REG_SCITXBUF, vecs[i].value);
    }

    ffrx = sci_case_wait_rxffst_at_least(count, timeout);
    if (((ffrx & SCIFFRX_FFST_MASK) >> 8) < count) {
        sci_fifo_capture(stage, count, ffrx);
        test_runtime_fail(level_fail_code);
    }

    for (i = 0U; i < count; ++i) {
        sci_fifo_check_byte((unsigned short)(vecs[i].value & 0x00FFU),
                            (unsigned short)(tag_base + i));
    }
}

static unsigned short wait_rxffint(unsigned long timeout)
{
    unsigned short ffrx = 0U;

    do {
        ffrx = sci_reg_read16(SCI_REG_SCIFFRX);
        if ((ffrx & SCIFFRX_FFINT_MASK) != 0U) {
            return ffrx;
        }
        timeout--;
    } while (timeout > 0UL);

    return ffrx;
}

static void expect_rxffil(unsigned short lvl, unsigned short idx)
{
    unsigned short rd;

    sci_reg_write16(SCI_REG_SCIFFRX,
                    (unsigned short)(SCIFFRX_FFRSTN_MASK |
                                     SCIFFRX_FFINTENA_MASK |
                                     (lvl & SCIFFRX_FFIL_MASK)));
    rd = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((rd & (SCIFFRX_FFRSTN_MASK | SCIFFRX_FFINTENA_MASK | SCIFFRX_FFIL_MASK)) !=
        (unsigned short)(SCIFFRX_FFRSTN_MASK | SCIFFRX_FFINTENA_MASK | (lvl & SCIFFRX_FFIL_MASK))) {
        test_runtime_fail(FAIL_RXTH + ((unsigned long)idx << 8) + (unsigned long)rd);
    }
}

static void expect_txffil(unsigned short lvl, unsigned short idx)
{
    unsigned short rd;

    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK |
                                     SCIFFTX_FFRSTN_MASK |
                                     SCIFFTX_FFINTENA_MASK |
                                     (lvl & SCIFFTX_FFIL_MASK)));
    rd = sci_reg_read16(SCI_REG_SCIFFTX);
    if ((rd & (SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFENA_MASK | SCIFFTX_FFRSTN_MASK |
              SCIFFTX_FFINTENA_MASK | SCIFFTX_FFIL_MASK)) !=
        (unsigned short)(SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFENA_MASK | SCIFFTX_FFRSTN_MASK |
                         SCIFFTX_FFINTENA_MASK | (lvl & SCIFFTX_FFIL_MASK))) {
        test_runtime_fail(FAIL_TXTH + ((unsigned long)idx << 8) + (unsigned long)rd);
    }
}

static void run_fifo_rx_basic(void)
{
    static const sci_fifo_vec_t rx_basic[] = {
        {0x0011U}, {0x0022U}, {0x0033U}, {0x0044U}
    };
    static const sci_fifo_vec_t level_basic[] = {
        {0x0011U}, {0x0022U}, {0x0033U}
    };
    static const sci_fifo_vec_t burst0[] = {
        {0x0012U}, {0x0034U}
    };
    static const sci_fifo_vec_t burst1[] = {
        {0x0056U}, {0x0078U}
    };

    sci_fifo_reinit(1U);
    sci_fifo_write_and_check(rx_basic,
                             (unsigned short)(sizeof(rx_basic) / sizeof(rx_basic[0])),
                             0U,
                             1U,
                             FAIL_LEVEL_RX4,
                             400000UL);

    sci_fifo_reinit(1U);
    sci_fifo_write_and_check(level_basic,
                             (unsigned short)(sizeof(level_basic) / sizeof(level_basic[0])),
                             16U,
                             2U,
                             FAIL_LEVEL_RX3,
                             400000UL);

    sci_fifo_reinit(1U);
    sci_fifo_write_and_check(burst0,
                             (unsigned short)(sizeof(burst0) / sizeof(burst0[0])),
                             32U,
                             3U,
                             FAIL_LEVEL_BURST0,
                             400000UL);
    sci_fifo_write_and_check(burst1,
                             (unsigned short)(sizeof(burst1) / sizeof(burst1[0])),
                             48U,
                             4U,
                             FAIL_LEVEL_BURST1,
                             400000UL);
}

static void run_fifo_irq_threshold(void)
{
    unsigned short ffrx;

    EALLOW;
    sci_reg_write16(SCI_REG_SCICCR, (unsigned short)(0x0007U | SCICCR_LOOPB_MASK));
    sci_reg_write16(SCI_REG_SCICTL1, (unsigned short)(SCICTL1_TXENA_MASK | SCICTL1_RXENA_MASK));
    sci_case_write_baud_div(3U);
    EDIS;

    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK |
                                     SCIFFTX_FFRSTN_MASK));
    sci_reg_write16(SCI_REG_SCIFFRX,
                    (unsigned short)(SCIFFRX_FFRSTN_MASK |
                                     SCIFFRX_FFINTENA_MASK |
                                     0x0002U));

    EALLOW;
    sci_reg_write16(SCI_REG_SCICTL1,
                    (unsigned short)(SCICTL1_SWRSTN_MASK |
                                     SCICTL1_TXENA_MASK |
                                     SCICTL1_RXENA_MASK));
    EDIS;

    sci_reg_write16(SCI_REG_SCITXBUF, 0x00C1U);
    sci_reg_write16(SCI_REG_SCITXBUF, 0x00C2U);

    ffrx = sci_case_wait_rxffst_at_least(2U, 300000UL);
    if (((ffrx & SCIFFRX_FFST_MASK) >> 8) < 2U) {
        test_runtime_fail(FAIL_NO_LVL + (unsigned long)ffrx);
    }

    ffrx = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((ffrx & SCIFFRX_FFINT_MASK) == 0U) {
        test_runtime_fail(FAIL_NO_INT + (unsigned long)ffrx);
    }
}

static void run_fifo_threshold_reprogram(void)
{
    unsigned short lvl;

    sci_fifo_reinit(1U);

    expect_rxffil(1U, 0U);
    expect_rxffil(4U, 1U);

    expect_txffil(0U, 0U);
    expect_txffil(3U, 1U);

    for (lvl = 0U; lvl <= 4U; ++lvl) {
        expect_txffil(lvl, (unsigned short)(lvl + 2U));
    }
}

static void run_fifo_rxint_clear_reassert(void)
{
    unsigned short ffrx;
    unsigned short rx;

    sci_fifo_reinit(2U);
    sci_reg_write16(SCI_REG_SCIFFRX, (unsigned short)(SCIFFRX_FFRSTN_MASK | SCIFFRX_FFINTENA_MASK | 2U));

    sci_reg_write16(SCI_REG_SCITXBUF, 0x0031U);
    sci_reg_write16(SCI_REG_SCITXBUF, 0x0032U);
    ffrx = wait_rxffint(300000UL);
    if ((ffrx & SCIFFRX_FFINT_MASK) == 0U) {
        test_runtime_fail(FAIL_INT_SET1 + (unsigned long)ffrx);
    }

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != 0x31U) {
        test_runtime_fail(FAIL_DRAIN0 + (unsigned long)sci_case_rx_byte(rx));
    }
    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != 0x32U) {
        test_runtime_fail(FAIL_DRAIN1 + (unsigned long)sci_case_rx_byte(rx));
    }

    sci_reg_write16(SCI_REG_SCIFFRX, (unsigned short)(SCIFFRX_FFRSTN_MASK | SCIFFRX_FFINTENA_MASK | SCIFFRX_FFINTCLR_MASK | 2U));
    ffrx = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((ffrx & SCIFFRX_FFINT_MASK) != 0U) {
        test_runtime_fail(FAIL_INT_CLR + (unsigned long)ffrx);
    }

    sci_reg_write16(SCI_REG_SCITXBUF, 0x0041U);
    sci_reg_write16(SCI_REG_SCITXBUF, 0x0042U);
    ffrx = wait_rxffint(300000UL);
    if ((ffrx & SCIFFRX_FFINT_MASK) == 0U) {
        test_runtime_fail(FAIL_INT_SET2 + (unsigned long)ffrx);
    }
}

void main(void)
{
    device_sdk_init();

    run_fifo_rx_basic();
    run_fifo_irq_threshold();
    run_fifo_threshold_reprogram();
    run_fifo_rxint_clear_reassert();

    test_runtime_pass();
}
