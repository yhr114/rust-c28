#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_INT_FLAG_SET     0x57D001UL
#define FAIL_INT_FLAG_CLEAR   0x57D002UL
#define FAIL_ROV_UNEXPECTED   0x57D003UL
#define FAIL_REARM_FLAG_SET   0x57D004UL

static unsigned short wait_status_set(unsigned short mask, unsigned long timeout)
{
    unsigned short st = 0U;

    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & mask) == mask) {
            return st;
        }
    } while (--timeout != 0UL);

    return st;
}

static unsigned short wait_status_clear(unsigned short mask, unsigned long timeout)
{
    unsigned short st = 0U;

    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & mask) == 0U) {
            return st;
        }
    } while (--timeout != 0UL);

    return st;
}

static void init_nonfifo_int_loopback(unsigned short cpha)
{
    unsigned short ctl;

    ctl = (unsigned short)(SPICTL_MASTER_MASK |
                           SPICTL_TALK_MASK |
                           SPICTL_INTENA_MASK |
                           (cpha ? SPICTL_CLKPHASE_MASK : 0U));

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
    spi_reg_write16(SPI_REG_SPICTL, ctl);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;

    spi_case_release_functional_reset_no_fifo();

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR,
                    (unsigned short)(SPICCR_SWRSTN_MASK |
                                     SPICCR_SPILBK_MASK |
                                     0x0007U));
    EDIS;
}

static void run_intflag_frame(unsigned short payload, unsigned long fail_base)
{
    unsigned short st;

    spi_case_write_tx_left_aligned(payload, 8U);
    st = wait_status_set(SPIST_INT_FLAG_MASK, 120000UL);
    if ((st & SPIST_INT_FLAG_MASK) == 0U) {
        test_runtime_fail(fail_base + (unsigned long)(st & 0x00FFU));
    }
    if ((st & SPIST_ROV_FLAG_MASK) != 0U) {
        test_runtime_fail(FAIL_ROV_UNEXPECTED + (unsigned long)(st & 0x00FFU));
    }

    (void)spi_reg_read16(SPI_REG_SPIRXBUF);
    st = wait_status_clear(SPIST_INT_FLAG_MASK, 120000UL);
    if ((st & SPIST_INT_FLAG_MASK) != 0U) {
        test_runtime_fail(FAIL_INT_FLAG_CLEAR + (unsigned long)(st & 0x00FFU));
    }
}

void main(void)
{
    device_sdk_init();

    init_nonfifo_int_loopback(0U);
    run_intflag_frame(0x003CU, FAIL_INT_FLAG_SET);
    run_intflag_frame(0x00C3U, FAIL_REARM_FLAG_SET);

    init_nonfifo_int_loopback(1U);
    run_intflag_frame(0x005AU, FAIL_INT_FLAG_SET + 0x100UL);
    run_intflag_frame(0x00A5U, FAIL_REARM_FLAG_SET + 0x100UL);

    test_runtime_pass();
}
