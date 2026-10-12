#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_CHARLEN_READBACK 0x521100U
#define FAIL_CHARLEN_TIMEOUT  0x521200U
#define SPIST_INT_FLAG_MASK   0x0040U

static void run_charlen(unsigned short charlen, unsigned long fail_base)
{
    unsigned long timeout;
    unsigned short rd;
    unsigned short st;

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | (charlen & 0x000FU)));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;

    rd = spi_reg_read16(SPI_REG_SPICCR);
    if ((rd & SPICCR_CHARLEN_MASK) != (charlen & SPICCR_CHARLEN_MASK)) {
        test_runtime_fail(fail_base + FAIL_CHARLEN_READBACK);
    }

    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SWRSTN_MASK | SPICCR_SPILBK_MASK | (charlen & 0x000FU)));
    EDIS;

    spi_reg_write16(SPI_REG_SPITXBUF, 0x00A5U);

    timeout = 100000UL;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            break;
        }
        timeout--;
    } while (timeout > 0UL);

    if (timeout == 0UL) {
        test_runtime_fail(fail_base + FAIL_CHARLEN_TIMEOUT + (unsigned long)(st & 0xFFU));
    }
}

void main(void)
{
    device_sdk_init();

    run_charlen(0x0000U, 0x0000U);
    run_charlen(0x0007U, 0x0100U);
    run_charlen(0x000FU, 0x0200U);

    test_runtime_pass();
}
