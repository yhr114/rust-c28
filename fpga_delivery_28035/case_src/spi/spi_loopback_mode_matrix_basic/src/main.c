#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_MODE_TIMEOUT_BASE 0x520100U
#define FAIL_MODE_DATA_BASE    0x520200U
#define SPIST_INT_FLAG_MASK    0x0040U

static void run_mode(unsigned short ccr_bits,
                     unsigned short ctl_bits,
                     unsigned short brr,
                     unsigned short tx_data,
                     unsigned long fail_base)
{
    unsigned long timeout;
    unsigned short st;
    unsigned short rx_data;
    unsigned short rx_byte;

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, ccr_bits);
    spi_reg_write16(SPI_REG_SPICTL, ctl_bits);
    spi_reg_write16(SPI_REG_SPIBRR, brr);
    EDIS;

    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(ccr_bits | SPICCR_SWRSTN_MASK));
    EDIS;

    spi_reg_write16(SPI_REG_SPITXBUF, tx_data);

    timeout = 100000UL;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            break;
        }
        timeout--;
    } while (timeout > 0UL);

    if (timeout == 0UL) {
        test_runtime_fail(fail_base + FAIL_MODE_TIMEOUT_BASE + (unsigned long)(st & 0xFFU));
    }

    rx_data = spi_reg_read16(SPI_REG_SPIRXBUF);
    rx_byte = (unsigned short)((rx_data >> 8) & 0x00FFU);
    if (rx_byte != tx_data) {
        test_runtime_fail(fail_base + FAIL_MODE_DATA_BASE + (unsigned long)rx_byte);
    }
}

void main(void)
{
    device_sdk_init();

    run_mode((unsigned short)(SPICCR_SPILBK_MASK | 0x0007U),
             (unsigned short)(SPICTL_MASTER_MASK | SPICTL_TALK_MASK),
             0x0003U, 0x004CU, 0x0000U);
    run_mode((unsigned short)(SPICCR_SPILBK_MASK | 0x0007U),
             (unsigned short)(SPICTL_MASTER_MASK | SPICTL_TALK_MASK | SPICTL_CLKPHASE_MASK),
             0x0003U, 0x0096U, 0x0100U);
    run_mode((unsigned short)(SPICCR_SPILBK_MASK | SPICCR_CLKPOL_MASK | 0x0007U),
             (unsigned short)(SPICTL_MASTER_MASK | SPICTL_TALK_MASK),
             0x0001U, 0x0033U, 0x0200U);
    run_mode((unsigned short)(SPICCR_SPILBK_MASK | SPICCR_CLKPOL_MASK | 0x0007U),
             (unsigned short)(SPICTL_MASTER_MASK | SPICTL_TALK_MASK | SPICTL_CLKPHASE_MASK),
             0x0007U, 0x00CCU, 0x0300U);

    test_runtime_pass();
}
