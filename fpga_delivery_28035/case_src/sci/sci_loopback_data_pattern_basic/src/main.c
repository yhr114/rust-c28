#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_RXRDY 0x59A001UL
#define FAIL_DATA0 0x59A002UL
#define FAIL_DATA1 0x59A003UL
#define FAIL_DATA2 0x59A004UL
#define FAIL_DATA3 0x59A005UL

void main(void)
{
    unsigned short rx;
    const unsigned short pat[4] = {0x00U, 0x55U, 0xAAU, 0xFFU};
    unsigned int i;

    device_sdk_init();
    sci_case_basic_init_no_fifo(SCICCR_LOOPB_MASK, 0U, 3U);

    for (i = 0U; i < 4U; ++i) {
        sci_reg_write16(SCI_REG_SCITXBUF, pat[i]);
        if ((sci_case_wait_rxrdy(20000UL) & SCIRXST_RXRDY_MASK) == 0U) {
            test_runtime_fail(FAIL_RXRDY + (unsigned long)i);
        }
        rx = sci_reg_read16(SCI_REG_SCIRXBUF);
        if (sci_case_rx_byte(rx) != pat[i]) {
            test_runtime_fail((FAIL_DATA0 + (unsigned long)i) + ((unsigned long)sci_case_rx_byte(rx) << 8));
        }
    }

    test_runtime_pass();
}
