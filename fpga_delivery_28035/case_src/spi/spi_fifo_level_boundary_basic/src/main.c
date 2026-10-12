#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_TXFFST_ZERO  0x533001UL
#define FAIL_TXFFST_FULL  0x533002UL
#define FAIL_TXFFST_DRAIN 0x533003UL

#define SPI_FIFO_DEPTH    4U
#define SPI_FIFO_TIMEOUT  200000UL

static unsigned short tx_fifo_level(void)
{
    return (unsigned short)((spi_reg_read16(SPI_REG_SPIFFTX) &
                             SPIFFTX_FFST_MASK) >> 8);
}

void main(void)
{
    unsigned int i;
    unsigned long timeout;
    unsigned short level;

    device_sdk_init();

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR,
                    (unsigned short)(SPICCR_SPILBK_MASK | 0x000FU));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x007FU);
    EDIS;

    spi_reg_write16(SPI_REG_SPIFFTX,
                    (unsigned short)(SPIFFTX_SPIRSTN_MASK |
                                     SPIFFTX_SPIFFENA_MASK |
                                     SPIFFTX_FFRSTN_MASK |
                                     0x0004U));
    spi_reg_write16(SPI_REG_SPIFFRX, SPIFFRX_FFRSTN_MASK);

    level = tx_fifo_level();
    if (level != 0U) {
        test_runtime_fail(FAIL_TXFFST_ZERO + (unsigned long)level);
    }

    /* Hold the shifter in reset so FIFO occupancy is deterministic. */
    for (i = 0U; i < SPI_FIFO_DEPTH; ++i) {
        spi_reg_write16(SPI_REG_SPITXBUF,
                        (unsigned short)(0x1100U + i));
    }

    level = tx_fifo_level();
    if (level != SPI_FIFO_DEPTH) {
        test_runtime_fail(FAIL_TXFFST_FULL + (unsigned long)level);
    }

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR,
                    (unsigned short)(SPICCR_SWRSTN_MASK |
                                     SPICCR_SPILBK_MASK |
                                     0x000FU));
    EDIS;

    timeout = SPI_FIFO_TIMEOUT;
    do {
        level = tx_fifo_level();
        if (level == 0U) {
            break;
        }
        timeout--;
    } while (timeout != 0UL);

    if (level != 0U) {
        test_runtime_fail(FAIL_TXFFST_DRAIN + (unsigned long)level);
    }

    test_runtime_pass();
}
