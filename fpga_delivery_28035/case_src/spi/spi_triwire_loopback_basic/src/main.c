#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_TRIWIRE_CFG   0x522001U
#define FAIL_TRIWIRE_TO    0x522002U
#define FAIL_TRIWIRE_DATA  0x522003U
#define SPIST_INT_FLAG_MASK 0x0040U

void main(void)
{
    unsigned long timeout;
    unsigned short rd;
    unsigned short st;
    unsigned short rx_data;
    unsigned short rx_byte;

    device_sdk_init();

    spi_reg_write16(SPI_REG_SPIPRI, (unsigned short)(SPIPRI_TRIWIRE_MASK));
    rd = spi_reg_read16(SPI_REG_SPIPRI);
    if ((rd & SPIPRI_TRIWIRE_MASK) == 0U) {
        test_runtime_fail(FAIL_TRIWIRE_CFG);
    }

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

    spi_reg_write16(SPI_REG_SPITXBUF, 0x005AU);

    timeout = 100000UL;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            break;
        }
        timeout--;
    } while (timeout > 0UL);

    if (timeout == 0UL) {
        test_runtime_fail(FAIL_TRIWIRE_TO + (unsigned long)(st & 0xFFU));
    }

    rx_data = spi_reg_read16(SPI_REG_SPIRXBUF);
    rx_byte = (unsigned short)((rx_data >> 8) & 0x00FFU);
    if (rx_byte != 0x005AU) {
        test_runtime_fail(FAIL_TRIWIRE_DATA + (unsigned long)rx_byte);
    }

    test_runtime_pass();
}
