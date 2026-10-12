#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_HI   0x588001UL
#define FAIL_LO   0x588002UL
#define FAIL_RX   0x588003UL
#define FAIL_DATA 0x588004UL

static void sci_drain_rxbuf(void)
{
    unsigned short st;
    unsigned short i;

    for (i = 0U; i < 4U; ++i) {
        st = sci_reg_read16(SCI_REG_SCIRXST);
        if ((st & SCIRXST_RXRDY_MASK) != 0U) {
            (void)sci_reg_read16(SCI_REG_SCIRXBUF);
        } else {
            break;
        }
    }
}

static void sci_program_baud_and_settle(unsigned short div)
{
    (void)sci_case_wait_txfree(400000UL);
    sci_drain_rxbuf();
    sci_case_write_baud_div(div);
    sci_case_delay(2048UL);
    sci_drain_rxbuf();
}

static void sci_send_and_expect(unsigned short txdata, unsigned short idx, unsigned long timeout)
{
    unsigned short rx;
    unsigned short st;

    sci_reg_write16(SCI_REG_SCITXBUF, txdata);
    st = sci_case_wait_rxrdy(timeout);
    if ((st & SCIRXST_RXRDY_MASK) == 0U) {
        test_runtime_fail(FAIL_RX + ((unsigned long)idx << 8) +
                          (unsigned long)sci_reg_read16(SCI_REG_SCIRXST));
    }
    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != (txdata & 0x00FFU)) {
        test_runtime_fail(FAIL_DATA + ((unsigned long)idx << 8) +
                          (unsigned long)sci_case_rx_byte(rx));
    }
}

static void sci_expect_baud_low(unsigned short div, unsigned short idx)
{
    unsigned short rd;

    rd = sci_reg_read16(SCI_REG_SCILBAUD);
    if ((rd & 0x00FFU) != div) {
        test_runtime_fail(FAIL_LO + ((unsigned long)idx << 8) + (unsigned long)rd);
    }
}

void main(void)
{
    static const unsigned short divs[] = {3U, 5U, 7U};
    static const unsigned short pats[] = {0x13U, 0x26U, 0x39U};
    unsigned short rd;
    unsigned short i;

    device_sdk_init();
    sci_case_basic_init_no_fifo(SCICCR_LOOPB_MASK, 0U, 0x0123U);

    rd = sci_reg_read16(SCI_REG_SCIHBAUD);
    if ((rd & 0x00FFU) != 0x0001U) {
        test_runtime_fail(FAIL_HI + (unsigned long)rd);
    }
    rd = sci_reg_read16(SCI_REG_SCILBAUD);
    if ((rd & 0x00FFU) != 0x0023U) {
        test_runtime_fail(FAIL_LO + (unsigned long)rd);
    }
    sci_send_and_expect(0x0037U, 0U, 400000UL);

    sci_program_baud_and_settle(3U);
    sci_send_and_expect(0x0025U, 1U, 400000UL);

    sci_program_baud_and_settle(5U);
    sci_expect_baud_low(5U, 2U);
    sci_send_and_expect(0x004AU, 2U, 400000UL);

    for (i = 0U; i < (unsigned short)(sizeof(divs) / sizeof(divs[0])); ++i) {
        sci_program_baud_and_settle(divs[i]);
        sci_expect_baud_low(divs[i], (unsigned short)(i + 3U));
        sci_send_and_expect(pats[i], (unsigned short)(i + 3U), 400000UL);
    }

    test_runtime_pass();
}
