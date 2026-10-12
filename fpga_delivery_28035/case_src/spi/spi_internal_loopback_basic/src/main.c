//#include "board_spi_case.h"
//#include "case_config.h"
//#include "test_runtime.h"
//
//#define FAIL_LOOPBACK_TIMEOUT 0x51A001U
//#define FAIL_LOOPBACK_DATA    0x51A002U
//
//void main(void)
//{
//    unsigned long timeout;
//    unsigned short rx_data;
//
//    device_sdk_init();
//
//    EALLOW;
//    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
//    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
//    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
//    EDIS;
//    spi_case_enable_fifo();
//    if ((spi_reg_read16(SPI_REG_SPIFFTX) & 0xE000U) != 0xE000U) {
//        test_runtime_fail(0x51A010U);
//    }
//    if ((spi_reg_read16(SPI_REG_SPIFFRX) & 0x2000U) != 0x2000U) {
//        test_runtime_fail(0x51A011U);
//    }
//    EALLOW;
//    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SWRSTN_MASK | SPICCR_SPILBK_MASK | 0x0007U));
//    EDIS;
//
//    spi_reg_write16(SPI_REG_SPITXBUF, 0x003CU);
//
//    timeout = 100000UL;
//    while (timeout > 0UL) {
//        rx_data = spi_reg_read16(SPI_REG_SPIRXBUF);
//        if ((rx_data & 0x00FFU) == 0x003CU) {
//            test_runtime_pass();
//        }
//        timeout--;
//    }
//
//    if (timeout == 0UL) {
//        test_runtime_fail(FAIL_LOOPBACK_TIMEOUT);
//    }
//
//    test_runtime_fail(FAIL_LOOPBACK_DATA);
//}

//#include "board_spi_case.h"
//#include "case_config.h"
//#include "test_runtime.h"
//
//#define FAIL_LOOPBACK_INT_TIMEOUT   0x51A001U
//#define FAIL_LOOPBACK_DATA          0x51A002U
//#define FAIL_LOOPBACK_TXFULL_STUCK  0x51A003U
//
//#define SPIST_INT_FLAG_MASK         0x0040U
//#define SPIST_TXFULL_FLAG_MASK      0x0020U
//
//void main(void)
//{
//    unsigned long timeout;
//    unsigned short st;
//    unsigned short rx_data;
//
//    device_sdk_init();
//
//    /*
//     * Basic internal loopback smoke test:
//     * - internal loopback enabled
//     * - FIFO disabled
//     * - master mode
//     * - TALK enabled
//     * - keep CPHA=1 because this RTL works better on this path
//     */
//    EALLOW;
//    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
//    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
//    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
//    EDIS;
//
//    /*
//     * Keep FIFO disabled for the most basic loopback path.
//     */
//    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
//    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);
//
//    /*
//     * Release SPI from software reset.
//     */
//    EALLOW;
//    spi_reg_write16(SPI_REG_SPICCR,
//                    (unsigned short)(SPICCR_SWRSTN_MASK |
//                                     SPICCR_SPILBK_MASK |
//                                     0x0007U));
//    EDIS;
//
//    /*
//     * Send one 8-bit value.
//     */
//    spi_reg_write16(SPI_REG_SPITXBUF, 0x003CU);
//
//    /*
//     * Wait until receive-done sets SPIST.INT_FLAG.
//     */
//    timeout = 100000UL;
//    do {
//        st = spi_reg_read16(SPI_REG_SPISTS);
//        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
//            break;
//        }
//        timeout--;
//    } while (timeout > 0UL);
//
//    if (timeout == 0UL) {
//        if ((st & SPIST_TXFULL_FLAG_MASK) != 0U) {
//            test_runtime_fail(FAIL_LOOPBACK_TXFULL_STUCK);
//        }
//        test_runtime_fail(FAIL_LOOPBACK_INT_TIMEOUT);
//    }
//
//    /*
//     * Read back received data after INT_FLAG is observed.
//     */
//    rx_data = spi_reg_read16(SPI_REG_SPIRXBUF);
//
//    if ((rx_data & 0x00FFU) != 0x003CU) {
//        test_runtime_fail(FAIL_LOOPBACK_DATA);
//    }
//
//    test_runtime_pass();
//}

#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_LOOPBACK_INT_TIMEOUT_BASE  0x51A100U
#define FAIL_LOOPBACK_DATA_BASE         0x51A200U
#define FAIL_LOOPBACK_TXFULL_STUCK      0x51A300U
#define FAIL_LOOPBACK_RXBUF_ZERO        0x51A400U

#define SPIST_ROV_FLAG_MASK             0x0080U
#define SPIST_INT_FLAG_MASK             0x0040U
#define SPIST_TXFULL_FLAG_MASK          0x0020U

void main(void)
{
    unsigned long timeout;
    unsigned short st;
    unsigned short rx_data;
    unsigned short rx_byte;

    device_sdk_init();

    /*
     * Basic internal loopback smoke test:
     * - internal loopback enabled
     * - master mode
     * - TALK enabled
     * - CPHA=1
     * - keep functional reset released by setting both SPIRSTn and FFRSTn
     * - FIFO datapath stays disabled because FFENA=0
     */
    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR, (unsigned short)(SPICCR_SPILBK_MASK | 0x0007U));
    spi_reg_write16(SPI_REG_SPICTL, 0x000EU);
    spi_reg_write16(SPI_REG_SPIBRR, 0x0003U);
    EDIS;

    /*
     * Important for this RTL:
     * SPIRSTn=1 and FFRSTn=1 are needed to release internal functional reset.
     * FFENA stays 0 so we still test the non-FIFO path.
     */
    spi_reg_write16(SPI_REG_SPIFFTX, 0xA000U);
    spi_reg_write16(SPI_REG_SPIFFRX, 0x2000U);

    /*
     * Release SPI from software reset.
     */
    EALLOW;
    spi_reg_write16(SPI_REG_SPICCR,
                    (unsigned short)(SPICCR_SWRSTN_MASK |
                                     SPICCR_SPILBK_MASK |
                                     0x0007U));
    EDIS;

    /*
     * Send one 8-bit value.
     */
    spi_reg_write16(SPI_REG_SPITXBUF, 0x003CU);

    /*
     * Wait until receive-done sets SPIST.INT_FLAG.
     */
    timeout = 100000UL;
    do {
        st = spi_reg_read16(SPI_REG_SPISTS);
        if ((st & SPIST_INT_FLAG_MASK) != 0U) {
            break;
        }
        timeout--;
    } while (timeout > 0UL);

    if (timeout == 0UL) {
        if ((st & SPIST_TXFULL_FLAG_MASK) != 0U) {
            test_runtime_fail(FAIL_LOOPBACK_TXFULL_STUCK +
                              (unsigned long)(st & 0x00FFU));
        }
        test_runtime_fail(FAIL_LOOPBACK_INT_TIMEOUT_BASE +
                          (unsigned long)(st & 0x00FFU));
    }

    /*
     * Read back received data after INT_FLAG is observed.
     * This RTL returns the 8-bit received value in SPIRXBUF[15:8].
     */
    rx_data = spi_reg_read16(SPI_REG_SPIRXBUF);

    if (rx_data == 0x0000U) {
        test_runtime_fail(FAIL_LOOPBACK_RXBUF_ZERO +
                          (unsigned long)(st & 0x00FFU));
    }

    rx_byte = (unsigned short)((rx_data >> 8) & 0x00FFU);

    if (rx_byte != 0x003CU) {
        test_runtime_fail(FAIL_LOOPBACK_DATA_BASE +
                          (unsigned long)rx_byte);
    }

    test_runtime_pass();
}
