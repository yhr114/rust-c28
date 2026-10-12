#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_CHARLEN 0x58F001UL

void main(void)
{
    unsigned short rd;
    unsigned short ch;

    device_sdk_init();

    for (ch = 0U; ch <= 7U; ++ch) {
        EALLOW;
        sci_reg_write16(SCI_REG_SCICCR,
                        (unsigned short)(SCICCR_LOOPB_MASK |
                                         SCICCR_IDLE_ADDR_MASK |
                                         ch));
        EDIS;
        rd = sci_reg_read16(SCI_REG_SCICCR);
        if ((rd & (SCICCR_LOOPB_MASK | SCICCR_IDLE_ADDR_MASK | SCICCR_CHAR_MASK)) !=
            (unsigned short)(SCICCR_LOOPB_MASK | SCICCR_IDLE_ADDR_MASK | ch)) {
            test_runtime_fail(FAIL_CHARLEN + ((unsigned long)ch << 8) + (unsigned long)rd);
        }
    }

    test_runtime_pass();
}
