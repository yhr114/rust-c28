#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_CTL2_CFG  0x5D9101UL
#define FAIL_TX_BUSY   0x5D9102UL
#define FAIL_RXRDY     0x5D9103UL
#define FAIL_RXDATA    0x5D9104UL
#define FAIL_TXFREE    0x5D9105UL

static void write_ctl2(unsigned short value)
{
    EALLOW;
    sci_reg_write16(SCI_REG_SCICTL2, value);
    EDIS;
}

static void expect_ctl2(unsigned short expected, unsigned short tag)
{
    unsigned short ctl2;

    ctl2 = sci_reg_read16(SCI_REG_SCICTL2);
    if ((ctl2 & (SCICTL2_RXBK_INTEN_MASK | SCICTL2_TX_INTEN_MASK)) != expected) {
        test_runtime_fail(FAIL_CTL2_CFG + ((unsigned long)tag << 8) + (unsigned long)ctl2);
    }
}

static void send_with_txint(unsigned short data, unsigned short tag)
{
    unsigned short st;
    unsigned short rx;
    unsigned short ctl2;

    ctl2 = sci_case_wait_txfree(300000UL);
    if ((ctl2 & (SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) !=
        (unsigned short)(SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) {
        test_runtime_fail(FAIL_TX_BUSY + ((unsigned long)tag << 8) + (unsigned long)ctl2);
    }

    write_ctl2(0U);
    expect_ctl2(0U, (unsigned short)(tag + 0x10U));
    write_ctl2(SCICTL2_TX_INTEN_MASK);
    expect_ctl2(SCICTL2_TX_INTEN_MASK, (unsigned short)(tag + 0x20U));

    sci_reg_write16(SCI_REG_SCITXBUF, data);

    st = sci_case_wait_rxrdy(300000UL);
    if ((st & SCIRXST_RXRDY_MASK) == 0U) {
        test_runtime_fail(FAIL_RXRDY + ((unsigned long)tag << 8) + (unsigned long)st);
    }

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != (data & 0x00FFU)) {
        test_runtime_fail(FAIL_RXDATA + ((unsigned long)tag << 8) +
                          (unsigned long)sci_case_rx_byte(rx));
    }

    ctl2 = sci_case_wait_txfree(300000UL);
    if ((ctl2 & (SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) !=
        (unsigned short)(SCICTL2_TXRDY_MASK | SCICTL2_TXEMPTY_MASK)) {
        test_runtime_fail(FAIL_TXFREE + ((unsigned long)tag << 8) + (unsigned long)ctl2);
    }

    sci_case_delay(1024UL);
}

void main(void)
{
    device_sdk_init();
    sci_case_route_scia_gpio28_29();
    sci_case_basic_init_no_fifo(SCICCR_LOOPB_MASK, 0U, 3U);

    send_with_txint(0x0055U, 1U);
    send_with_txint(0x00A5U, 2U);

    write_ctl2(0U);
    expect_ctl2(0U, 3U);

    test_runtime_pass();
}
