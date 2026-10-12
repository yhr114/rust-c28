#include "board_spi_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define WAIT_LIMIT 200000UL
#define FAIL_CONFIG 0x533101UL
#define FAIL_TX_EMPTY 0x533102UL
#define FAIL_RX_LEVEL 0x533110UL
#define FAIL_RX_TIMEOUT 0x533120UL
#define FAIL_DATA 0x533130UL
#define FAIL_RX_OVERFLOW 0x533140UL

volatile unsigned short rx_levels[9];
volatile unsigned short received[4];
volatile unsigned short progress = 0;
static const unsigned short words[4] = {0x0011U, 0xA55AU, 0x5AA5U, 0x1234U};

static unsigned short rx_level(void)
{
    return (SpiaRegs.SPIFFRX.all >> 8) & 0x001FU;
}

static void wait_rx_level(unsigned short expected)
{
    unsigned long n;
    unsigned short status, level;
    for (n = 0; n < WAIT_LIMIT; ++n) {
        status = SpiaRegs.SPIFFRX.all;
        if (status & 0x8000U) test_runtime_fail(FAIL_RX_OVERFLOW);
        level = (status >> 8) & 0x001FU;
        if (level == expected) return;
        if (level > expected) test_runtime_fail(FAIL_RX_LEVEL + expected);
    }
    test_runtime_fail(FAIL_RX_TIMEOUT + expected);
}

static void wait_tx_empty(void)
{
    unsigned long n;
    for (n = 0; n < WAIT_LIMIT; ++n)
        if ((SpiaRegs.SPIFFTX.all & 0x1F00U) == 0) return;
    test_runtime_fail(FAIL_TX_EMPTY);
}

void main(void)
{
    unsigned short i;
    device_sdk_init();

    /* Explicit 16-bit internal loopback master. Reset both FIFO pointers
       before releasing them. No external SPI wiring is required. */
    SpiaRegs.SPICCR.all = 0x001FU;
    SpiaRegs.SPICTL.all = 0x0006U;
    SpiaRegs.SPIBRR = 0x007FU;
    SpiaRegs.SPIFFTX.all = 0x4000U;
    SpiaRegs.SPIFFRX.all = 0x0044U;
    SpiaRegs.SPIFFCT.all = 0;
    SpiaRegs.SPIFFTX.all = 0xE040U;
    SpiaRegs.SPIFFRX.all = 0x6044U;
    if ((SpiaRegs.SPIFFTX.all & 0xE000U) != 0xE000U ||
        (SpiaRegs.SPIFFRX.all & 0x2000U) == 0)
        test_runtime_fail(FAIL_CONFIG);
    wait_tx_empty();
    if (rx_level() != 0) test_runtime_fail(FAIL_RX_LEVEL);
    rx_levels[0] = rx_level();
    SpiaRegs.SPICCR.all = 0x009FU;

    /* On F28035 each FIFO is four words deep. Wait for each word to
       arrive, but retain received words so RXFFST grows from 0 to 4.
       A TX word may leave its FIFO immediately; do not assert TXFFST>0. */
    for (i = 0; i < 4; ++i) {
        SpiaRegs.SPITXBUF = words[i];
        wait_rx_level(i + 1U);
        rx_levels[i + 1U] = rx_level();
        progress = i + 1U;
    }
    wait_tx_empty();

    /* No more transmissions: every read must reduce RXFFST by one. */
    for (i = 0; i < 4; ++i) {
        received[i] = SpiaRegs.SPIRXBUF;
        if (received[i] != words[i]) test_runtime_fail(FAIL_DATA + i);
        /* Allow the peripheral read-side count update to settle. */
        {
            unsigned long n;
            for (n = 0; n < WAIT_LIMIT; ++n)
                if (rx_level() == 3U - i) break;
            if (n == WAIT_LIMIT) test_runtime_fail(FAIL_RX_LEVEL + 8U + i);
        }
        rx_levels[5U + i] = rx_level();
        progress = 5U + i;
    }
    if (SpiaRegs.SPIFFRX.all & 0x8000U) test_runtime_fail(FAIL_RX_OVERFLOW);
    wait_tx_empty();
    test_runtime_pass();
}
