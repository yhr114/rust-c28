#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_SPICCR  0x510001U
#define FAIL_SPICTL  0x510002U
#define FAIL_SPIBRR  0x510003U
#define FAIL_SPIFFCT 0x510004U
#define FAIL_SPIPRI  0x510005U

static void expect_rw(unsigned int off,
                      unsigned short wr,
                      unsigned short mask,
                      unsigned long fail_code)
{
    unsigned short rd;
    spi_reg_write16(off, wr);
    rd = spi_reg_read16(off);
    if ((rd & mask) != (wr & mask)) {
        test_runtime_fail(fail_code);
    }
}

void main(void)
{
    device_sdk_init();

    EALLOW;
    expect_rw(SPI_REG_SPICCR, 0x00D7U, SPICCR_VALID_MASK, FAIL_SPICCR);
    expect_rw(SPI_REG_SPICTL, 0x001FU, SPICTL_VALID_MASK, FAIL_SPICTL);
    expect_rw(SPI_REG_SPIBRR, 0x007FU, SPIBRR_VALID_MASK, FAIL_SPIBRR);
    EDIS;

    expect_rw(SPI_REG_SPIFFCT, 0x0055U, SPIFFCT_TXDLY_MASK, FAIL_SPIFFCT);
    expect_rw(SPI_REG_SPIPRI, 0x0073U, SPIPRI_VALID_MASK, FAIL_SPIPRI);

    test_runtime_pass();
}
