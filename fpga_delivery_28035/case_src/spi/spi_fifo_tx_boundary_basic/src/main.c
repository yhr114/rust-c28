#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_CFG1   0x533001UL
#define FAIL_CFG4   0x533002UL
#define FAIL_CFG8   0x533003UL
#define FAIL_WR0    0x533004UL
#define FAIL_WR1    0x533005UL
#define FAIL_WR2    0x533006UL
#define FAIL_WR3    0x533007UL
#define FAIL_TXTH_CFG      0x533008UL
#define FAIL_TXIRQ_TIMEOUT 0x533009UL

static void check_txff(unsigned short wr, unsigned long fail_code)
{
    unsigned short rd;

    spi_reg_write16(SPI_REG_SPIFFTX, wr);
    rd = spi_reg_read16(SPI_REG_SPIFFTX);
    if ((rd & (SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK | SPIFFTX_TXFFIL_MASK)) !=
        (wr & (SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK | SPIFFTX_TXFFIL_MASK))) {
        test_runtime_fail(fail_code + (unsigned long)rd);
    }
}

static void write_tx_smoke(unsigned short tx, unsigned long fail_code)
{
    unsigned short rd_before;
    unsigned short rd_after;

    rd_before = spi_reg_read16(SPI_REG_SPIFFTX);
    spi_reg_write16(SPI_REG_SPITXBUF, tx);
    rd_after = spi_reg_read16(SPI_REG_SPIFFTX);

    if ((rd_after & (SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK)) !=
        (rd_before & (SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK))) {
        test_runtime_fail(fail_code + (unsigned long)rd_after);
    }
}

static void check_txff_threshold_irq(void)
{
    unsigned long timeout;
    unsigned short rd;

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, 0x0007U);
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;

    spi_reg_write16(SPI_REG_SPIFFTX, 0xE021U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);
    rd = spi_reg_read16(SPI_REG_SPIFFTX);
    if ((rd & 0xE03FU) != 0xE021U) {
        test_runtime_fail(FAIL_TXTH_CFG + (unsigned long)rd);
    }

    timeout = 100000UL;
    do {
        if ((spi_reg_read16(SPI_REG_SPIFFTX) & SPIFFTX_TXFFINT_MASK) != 0U) {
            return;
        }
        timeout--;
    } while (timeout > 0UL);

    test_runtime_fail(FAIL_TXIRQ_TIMEOUT);
}

void main(void)
{
    device_sdk_init();

    check_txff_threshold_irq();

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);

    check_txff((unsigned short)(SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK | 0x0001U), FAIL_CFG1);
    check_txff((unsigned short)(SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK | 0x0004U), FAIL_CFG4);
    check_txff((unsigned short)(SPIFFTX_SPIRSTN_MASK | SPIFFTX_SPIFFENA_MASK | 0x0008U), FAIL_CFG8);

    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SWRSTN_MASK | SPICCR_SPILBK_MASK | 0x0007U));
    EDIS;

    write_tx_smoke(0x0011U, FAIL_WR0);
    write_tx_smoke(0x0022U, FAIL_WR1);
    write_tx_smoke(0x0033U, FAIL_WR2);
    write_tx_smoke(0x0044U, FAIL_WR3);

    test_runtime_pass();
}
