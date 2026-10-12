#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_FRAME0_TO   0x536001U
#define FAIL_FRAME1_TO   0x536002U
#define FAIL_FRAME0_DATA 0x536003U
#define FAIL_FRAME1_DATA 0x536004U
#define SPIST_INT_FLAG_MASK 0x0040U

static unsigned short run_frame(unsigned short tx, unsigned long fail_to)
{
    unsigned long timeout;
    unsigned short st;

    spi_reg_write16(SPI_REG_SPITXBUF, tx);
    timeout = 100000UL;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            return spi_reg_read16(SPI_REG_SPIRXBUF);
        }
        timeout--;
    } while (timeout > 0UL);

    test_runtime_fail(fail_to + (unsigned long)(st & 0xFFU));
    return 0U;
}

void main(void)
{
    unsigned short rx0;
    unsigned short rx1;

    device_sdk_init();

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;
    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);
    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SWRSTN_MASK | SPICCR_SPILBK_MASK | 0x0007U));
    EDIS;

    rx0 = run_frame(0x0012U, FAIL_FRAME0_TO);
    rx1 = run_frame(0x0034U, FAIL_FRAME1_TO);

    if (((rx0 >> 8) & 0xFFU) != 0x0012U) {
        test_runtime_fail(FAIL_FRAME0_DATA + (unsigned long)((rx0 >> 8) & 0xFFU));
    }
    if (((rx1 >> 8) & 0xFFU) != 0x0034U) {
        test_runtime_fail(FAIL_FRAME1_DATA + (unsigned long)((rx1 >> 8) & 0xFFU));
    }

    test_runtime_pass();
}
