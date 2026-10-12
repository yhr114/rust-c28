#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_RXRDY_SET   0x591001UL
#define FAIL_RXDATA      0x591002UL
#define FAIL_RXRDY_CLEAR 0x591003UL

void main(void)
{
    unsigned short st;
    unsigned short rx;
    unsigned long timeout;

    device_sdk_init();
    sci_case_basic_init_no_fifo(SCICCR_LOOPB_MASK, 0U, 3U);

    sci_reg_write16(SCI_REG_SCITXBUF, 0x003CU);
    st = sci_case_wait_rxrdy(20000UL);
    if ((st & SCIRXST_RXRDY_MASK) == 0U) {
        test_runtime_fail(FAIL_RXRDY_SET + (unsigned long)st);
    }

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != 0x3CU) {
        test_runtime_fail(FAIL_RXDATA + (unsigned long)sci_case_rx_byte(rx));
    }

    timeout = 20000UL;
    do {
        st = sci_reg_read16(SCI_REG_SCIRXST);
        if ((st & SCIRXST_RXRDY_MASK) == 0U) {
            test_runtime_pass();
        }
        timeout--;
    } while (timeout > 0UL);

    test_runtime_fail(FAIL_RXRDY_CLEAR + (unsigned long)st);
}
