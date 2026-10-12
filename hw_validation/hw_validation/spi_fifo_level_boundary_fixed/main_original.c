#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_TXFFST_ZERO   0x533001U
#define FAIL_TXFFST_NONZERO 0x533002U

void main(void)
{
    unsigned short rd;

    device_sdk_init();

    spi_reg_write16(SPI_REG_SPIFFTX, 0xE000U);
    rd = spi_reg_read16(SPI_REG_SPIFFTX);
    if ((rd & 0x1F00U) != 0x0000U) {
        test_runtime_fail(FAIL_TXFFST_ZERO + (unsigned long)((rd >> 8) & 0x1FU));
    }

    spi_reg_write16(SPI_REG_SPITXBUF, 0x0011U);
    rd = spi_reg_read16(SPI_REG_SPIFFTX);
    if ((rd & 0x1F00U) == 0x0000U) {
        test_runtime_fail(FAIL_TXFFST_NONZERO);
    }

    test_runtime_pass();
}
