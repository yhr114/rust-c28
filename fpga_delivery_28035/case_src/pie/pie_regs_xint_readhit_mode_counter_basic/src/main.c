#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "PIE TB-assisted XINT register coverage case supports VERSION=28035 only"
#endif
#include "device_28035.h"

#define REG16(addr_) (*(volatile Uint16 *)(addr_))
#define PIE_XINT1CR   0x00007070UL
#define PIE_XINT2CR   0x00007071UL
#define PIE_XINT3CR   0x00007072UL

static void check_xint_cr(Uint16 got, Uint16 exp, Uint16 fail_code)
{
    /* Only implemented bits [3:2] and [0] are expected to read back. */
    if ((got & 0x000DU) != (exp & 0x000DU)) {
        test_runtime_fail(fail_code);
    }
}

static void write_read_xint_crs(Uint16 cr1, Uint16 cr2, Uint16 cr3, Uint16 fail_base)
{
    REG16(PIE_XINT1CR) = cr1;
    REG16(PIE_XINT2CR) = cr2;
    REG16(PIE_XINT3CR) = cr3;

    check_xint_cr(REG16(PIE_XINT1CR), cr1, (Uint16)(fail_base + 0U));
    check_xint_cr(REG16(PIE_XINT2CR), cr2, (Uint16)(fail_base + 1U));
    check_xint_cr(REG16(PIE_XINT3CR), cr3, (Uint16)(fail_base + 2U));
}

void main(void)
{
    unsigned long loops;

    board_demo_init();
    DINT;
    IER = 0U;
    IFR = 0U;
    PieCtrlRegs.PIECTRL.bit.ENPIE = 0U;
    PieCtrlRegs.PIEACK.all = 0x0FFFU;

    write_read_xint_crs(0x0000U, 0x0000U, 0x0000U, PIE_REGS_XINT_FAIL_CLR0_BASE);
    write_read_xint_crs(0x0001U, 0x0005U, 0x000DU, PIE_REGS_XINT_FAIL_SET1_BASE);
    write_read_xint_crs(0x0000U, 0x0004U, 0x000CU, PIE_REGS_XINT_FAIL_CLR1_BASE);

    for (loops = 0UL; loops < PIE_REGS_XINT_READHIT_WAIT_LOOPS; ++loops) {
        asm(" NOP");
    }

    board_demo_toggle();
    test_runtime_pass();
}
