#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_CLR0  0x5A0101UL
#define FAIL_CLR1  0x5A0102UL
#define FAIL_FFST  0x5A0103UL
#define FAIL_DATA  0x5A0104UL

static void expect_fifo_level_at_least(unsigned short level, unsigned long tag, unsigned long timeout)
{
    unsigned short rd;

    rd = sci_case_wait_rxffst_at_least(level, timeout);
    if (((rd & SCIFFRX_FFST_MASK) >> 8) < level) {
        test_runtime_fail(FAIL_FFST + tag + (unsigned long)rd);
    }
}

static void expect_fifo_empty(unsigned long tag)
{
    unsigned short rd;

    rd = sci_case_wait_rxffst_at_least(1U, 1024UL);
    if (((rd & SCIFFRX_FFST_MASK) >> 8) != 0U) {
        test_runtime_fail(FAIL_CLR1 + tag + (unsigned long)rd);
    }
}

static void expect_rx_byte(unsigned short exp, unsigned long tag)
{
    unsigned short rd;

    rd = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rd) != (exp & 0x00FFU)) {
        test_runtime_fail(FAIL_DATA + tag + (unsigned long)sci_case_rx_byte(rd));
    }
}

static void reset_rx_fifo(unsigned short rxffil)
{
    sci_reg_write16(SCI_REG_SCIFFRX, (unsigned short)(rxffil & SCIFFRX_FFIL_MASK));
    sci_reg_write16(SCI_REG_SCIFFRX,
                    (unsigned short)(SCIFFRX_FFRSTN_MASK | (rxffil & SCIFFRX_FFIL_MASK)));
}

static void run_reset_then_loopback(void)
{
    unsigned short rd;

    sci_case_basic_init_fifo_loopback(0U, 3U, 1U, 0U);

    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK |
                                     0x0000U));
    rd = sci_reg_read16(SCI_REG_SCIFFTX);
    if ((rd & SCIFFTX_FFRSTN_MASK) != 0U) {
        test_runtime_fail(FAIL_CLR0 + (unsigned long)rd);
    }

    sci_reg_write16(SCI_REG_SCIFFTX,
                    (unsigned short)(SCIFFTX_SCIRSTN_MASK |
                                     SCIFFTX_FFENA_MASK |
                                     SCIFFTX_FFRSTN_MASK));
    reset_rx_fifo(0U);
    rd = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((rd & SCIFFRX_FFRSTN_MASK) == 0U) {
        test_runtime_fail(FAIL_CLR1 + (unsigned long)rd);
    }

    sci_reg_write16(SCI_REG_SCITXBUF, 0x0066U);
    expect_fifo_level_at_least(1U, 0x0000UL, 30000UL);
    expect_rx_byte(0x0066U, 0x0000UL);
}

static void run_rearm_after_reset(void)
{
    sci_case_basic_init_fifo_loopback(0U, 3U, 1U, 0U);

    sci_reg_write16(SCI_REG_SCITXBUF, 0x0041U);
    sci_reg_write16(SCI_REG_SCITXBUF, 0x0042U);
    expect_fifo_level_at_least(2U, 0x0100UL, 120000UL);

    reset_rx_fifo(1U);
    expect_fifo_empty(0x0200UL);

    sci_reg_write16(SCI_REG_SCITXBUF, 0x0055U);
    expect_fifo_level_at_least(1U, 0x0300UL, 120000UL);
    expect_rx_byte(0x0055U, 0x0300UL);
}

void main(void)
{
    device_sdk_init();

    run_reset_then_loopback();
    run_rearm_after_reset();

    test_runtime_pass();
}
