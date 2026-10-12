#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_TIMEOUT0      0x534001UL
#define FAIL_TIMEOUT1      0x534002UL
#define FAIL_TIMEOUT2      0x534003UL
#define FAIL_RX0           0x534004UL
#define FAIL_RX1           0x534005UL
#define FAIL_RX2           0x534006UL
#define FAIL_CFG           0x534007UL
#define SPIST_INT_FLAG_MASK 0x0040U

static void wait_int_flag(unsigned long fail_code)
{
    unsigned long timeout = 100000UL;
    unsigned short st = 0U;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            return;
        }
        timeout--;
    } while (timeout > 0UL);
    test_runtime_fail(fail_code + (unsigned long)(st & 0x00FFU));
}

static void send_and_check(unsigned short tx, unsigned long fail_to, unsigned long fail_rx)
{
    unsigned short rx;
    unsigned short rx_byte;
    spi_reg_write16(SPI_REG_SPITXBUF, tx);
    wait_int_flag(fail_to);
    rx = spi_reg_read16(SPI_REG_SPIRXBUF);
    rx_byte = (unsigned short)((rx >> 8) & 0x00FFU);
    if (rx_byte != tx) {
        test_runtime_fail(fail_rx + (unsigned long)rx_byte);
    }
}

void main(void)
{
    unsigned short rd;

    device_sdk_init();

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;
    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2003U);
    rd = spi_reg_read16(SPI_REG_SPIFFRX);
    if ((rd & SPIFFRX_RXFFIL_MASK) != 0x0003U) {
        test_runtime_fail(FAIL_CFG + (unsigned long)rd);
    }

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SWRSTN_MASK | SPICCR_SPILBK_MASK | 0x0007U));
    EDIS;

    send_and_check(0x005AU, FAIL_TIMEOUT0, FAIL_RX0);
    send_and_check(0x00A5U, FAIL_TIMEOUT1, FAIL_RX1);
    send_and_check(0x003CU, FAIL_TIMEOUT2, FAIL_RX2);

    test_runtime_pass();
}
