#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_RXRDY  0x582001UL
#define FAIL_RXDATA 0x582002UL
#define FAIL_RXST   0x582003UL

typedef struct {
    unsigned short sciccr_extra;
    unsigned short txdata;
    unsigned short err_mask;
    unsigned long timeout;
} sci_loop_profile_t;

static void sci_run_loopback_profile(const sci_loop_profile_t *profile, unsigned short idx)
{
    unsigned short st;
    unsigned short rx;

    sci_case_basic_init_no_fifo(profile->sciccr_extra, 0U, 3U);

    sci_reg_write16(SCI_REG_SCITXBUF, profile->txdata);
    st = sci_case_wait_rxrdy(profile->timeout);
    if ((st & SCIRXST_RXRDY_MASK) == 0U) {
        test_runtime_fail(FAIL_RXRDY + ((unsigned long)idx << 8) + (unsigned long)st);
    }

    rx = sci_reg_read16(SCI_REG_SCIRXBUF);
    if (sci_case_rx_byte(rx) != (profile->txdata & 0x00FFU)) {
        test_runtime_fail(FAIL_RXDATA + ((unsigned long)idx << 8) +
                          (unsigned long)sci_case_rx_byte(rx));
    }

    st = sci_reg_read16(SCI_REG_SCIRXST);
    if ((st & profile->err_mask) != 0U) {
        test_runtime_fail(FAIL_RXST + ((unsigned long)idx << 8) + (unsigned long)st);
    }
}

void main(void)
{
    static const sci_loop_profile_t profiles[] = {
        {SCICCR_LOOPB_MASK, 0x003CU,
         (unsigned short)(SCIRXST_RXERR_MASK | SCIRXST_FE_MASK | SCIRXST_PE_MASK | SCIRXST_OE_MASK),
         200000UL},
        {(unsigned short)(SCICCR_LOOPB_MASK | SCICCR_PARITY_EN_MASK), 0x0055U,
         (unsigned short)(SCIRXST_PE_MASK | SCIRXST_FE_MASK | SCIRXST_OE_MASK | SCIRXST_RXERR_MASK),
         200000UL},
        {(unsigned short)(SCICCR_LOOPB_MASK | SCICCR_PARITY_EN_MASK | SCICCR_PARITY_MASK), 0x003CU,
         (unsigned short)(SCIRXST_PE_MASK | SCIRXST_FE_MASK | SCIRXST_OE_MASK | SCIRXST_RXERR_MASK),
         250000UL},
        {(unsigned short)(SCICCR_LOOPB_MASK | SCICCR_STOP_MASK), 0x00A6U,
         (unsigned short)(SCIRXST_FE_MASK | SCIRXST_RXERR_MASK),
         250000UL}
    };
    unsigned short i;

    device_sdk_init();

    for (i = 0U; i < (unsigned short)(sizeof(profiles) / sizeof(profiles[0])); ++i) {
        sci_run_loopback_profile(&profiles[i], i);
    }

    test_runtime_pass();
}
