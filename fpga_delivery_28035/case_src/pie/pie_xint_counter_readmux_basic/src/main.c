#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "pie_xint_counter_readmux_basic supports VERSION=28035 only"
#endif
#include "device_28035.h"

#define REG16(addr_) (*(volatile Uint16 *)(addr_))
#define PIE_XINT1CR   0x00007070UL
#define PIE_XINT2CR   0x00007071UL
#define PIE_XINT3CR   0x00007072UL
#define PIE_XINT1CTR  0x00007078UL
#define PIE_XINT2CTR  0x00007079UL
#define PIE_XINT3CTR  0x0000707AUL

static void wait_for_xint_counters(void)
{
    unsigned long loops;
    for (loops = 0UL; loops < PIE_XINT_COUNTER_WAIT_LOOPS; ++loops) {
        asm(" NOP");
    }
}

void main(void)
{
    Uint16 cr1;
    Uint16 cr2;
    Uint16 cr3;
    Uint16 ctr1;
    Uint16 ctr2;
    Uint16 ctr3;
    Uint32 signature;

    board_demo_init();

    REG16(PIE_XINT1CR) = 0x0001U;
    REG16(PIE_XINT2CR) = 0x0005U;
    REG16(PIE_XINT3CR) = 0x000DU;
    wait_for_xint_counters();

    cr1 = REG16(PIE_XINT1CR);
    cr2 = REG16(PIE_XINT2CR);
    cr3 = REG16(PIE_XINT3CR);
    ctr1 = REG16(PIE_XINT1CTR);
    ctr2 = REG16(PIE_XINT2CTR);
    ctr3 = REG16(PIE_XINT3CTR);

    REG16(PIE_XINT1CR) = 0x0000U;
    REG16(PIE_XINT2CR) = 0x0000U;
    REG16(PIE_XINT3CR) = 0x0000U;

    signature = (Uint32)cr1 + (Uint32)cr2 + (Uint32)cr3 +
                (Uint32)ctr1 + (Uint32)ctr2 + (Uint32)ctr3;
    if ((cr1 & 0x0001U) == 0U || (cr2 & 0x0001U) == 0U || (cr3 & 0x0001U) == 0U) {
        test_runtime_fail(PIE_XINT_COUNTER_FAIL_CR);
    }
    if (signature == 0UL) {
        test_runtime_fail(PIE_XINT_COUNTER_FAIL_SIGNATURE);
    }

    board_demo_toggle();
    test_runtime_pass();
}
