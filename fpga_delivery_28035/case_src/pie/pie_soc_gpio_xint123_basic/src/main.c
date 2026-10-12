#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "pie_soc_gpio_xint123_basic only supports VERSION=28035"
#endif

#include "device_28035.h"

#define REG16(addr_) (*(volatile Uint16 *)(addr_))
#define PIE_XINT1CR   0x00007070UL
#define PIE_XINT2CR   0x00007071UL
#define PIE_XINT3CR   0x00007072UL

volatile Uint16 g_pie_soc_gpio_xint_stage;
volatile Uint16 g_pie_soc_gpio_xint_cr1;
volatile Uint16 g_pie_soc_gpio_xint_cr2;
volatile Uint16 g_pie_soc_gpio_xint_cr3;
volatile Uint16 g_pie_soc_gpio_xint_sel1;
volatile Uint16 g_pie_soc_gpio_xint_sel2;
volatile Uint16 g_pie_soc_gpio_xint_sel3;
volatile Uint16 g_pie_soc_gpio_xint_done;

static void fail_if(Uint16 condition, Uint16 code)
{
    if (condition != 0U) {
        test_runtime_fail(code);
    }
}

static void configure_gpio0_xint_sources(void)
{
    EALLOW;
    GpioCtrlRegs.GPAMUX1.bit.GPIO0 = 0U;
    GpioCtrlRegs.GPADIR.bit.GPIO0 = 0U;
    GpioCtrlRegs.GPAQSEL1.bit.GPIO0 = 3U;
    GpioCtrlRegs.GPAPUD.bit.GPIO0 = 0U;

    GpioIntRegs.GPIOXINT1SEL.bit.GPIOSEL = 0U;
    GpioIntRegs.GPIOXINT2SEL.bit.GPIOSEL = 0U;
    GpioIntRegs.GPIOXINT3SEL.bit.GPIOSEL = 0U;

    XIntruptRegs.XINT1CR.all = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
    XIntruptRegs.XINT2CR.all = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
    XIntruptRegs.XINT3CR.all = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
    EDIS;

    REG16(PIE_XINT1CR) = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
    REG16(PIE_XINT2CR) = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
    REG16(PIE_XINT3CR) = PIE_SOC_GPIO_XINT_DUALEDGE_EN;
}

static void sample_and_check_config(void)
{
    g_pie_soc_gpio_xint_sel1 = GpioIntRegs.GPIOXINT1SEL.all;
    g_pie_soc_gpio_xint_sel2 = GpioIntRegs.GPIOXINT2SEL.all;
    g_pie_soc_gpio_xint_sel3 = GpioIntRegs.GPIOXINT3SEL.all;
    g_pie_soc_gpio_xint_cr1 = REG16(PIE_XINT1CR);
    g_pie_soc_gpio_xint_cr2 = REG16(PIE_XINT2CR);
    g_pie_soc_gpio_xint_cr3 = REG16(PIE_XINT3CR);

    fail_if((Uint16)(g_pie_soc_gpio_xint_sel1 & 0x001FU) != 0U,
            PIE_SOC_GPIO_XINT_FAIL_SEL1);
    fail_if((Uint16)(g_pie_soc_gpio_xint_sel2 & 0x001FU) != 0U,
            PIE_SOC_GPIO_XINT_FAIL_SEL2);
    fail_if((Uint16)(g_pie_soc_gpio_xint_sel3 & 0x001FU) != 0U,
            PIE_SOC_GPIO_XINT_FAIL_SEL3);
    fail_if((Uint16)(g_pie_soc_gpio_xint_cr1 & 0x000DU) != PIE_SOC_GPIO_XINT_DUALEDGE_EN,
            PIE_SOC_GPIO_XINT_FAIL_CR1);
    fail_if((Uint16)(g_pie_soc_gpio_xint_cr2 & 0x000DU) != PIE_SOC_GPIO_XINT_DUALEDGE_EN,
            PIE_SOC_GPIO_XINT_FAIL_CR2);
    fail_if((Uint16)(g_pie_soc_gpio_xint_cr3 & 0x000DU) != PIE_SOC_GPIO_XINT_DUALEDGE_EN,
            PIE_SOC_GPIO_XINT_FAIL_CR3);
}

void main(void)
{
    unsigned long loop;

    board_demo_init();
    DINT;
    IER = 0x0000U;
    IFR = 0x0000U;
    PieCtrlRegs.PIECTRL.bit.ENPIE = 0U;
    PieCtrlRegs.PIEACK.all = 0x0FFFU;

    g_pie_soc_gpio_xint_stage = 1U;
    configure_gpio0_xint_sources();
    sample_and_check_config();

    g_pie_soc_gpio_xint_stage = 2U;
    for (loop = 0UL; loop < PIE_SOC_GPIO_XINT_WAIT_LOOPS; loop++) {
        asm(" NOP");
    }

    XIntruptRegs.XINT1CR.all = 0U;
    XIntruptRegs.XINT2CR.all = 0U;
    XIntruptRegs.XINT3CR.all = 0U;
    REG16(PIE_XINT1CR) = 0U;
    REG16(PIE_XINT2CR) = 0U;
    REG16(PIE_XINT3CR) = 0U;

    g_pie_soc_gpio_xint_done = 1U;
    g_pie_soc_gpio_xint_stage = 3U;
    board_demo_toggle();
    test_runtime_pass();
}
