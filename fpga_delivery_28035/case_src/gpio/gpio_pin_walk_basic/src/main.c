#include "board_gpio_case.h"
#include "case_config.h"
#include "test_runtime.h"

static void gpio_pin_walk_delay(void)
{
    board_delay_us(GPIO_PIN_WALK_BASIC_STEP_DELAY_US);
}

static void gpio_pin_walk_drive_a(Uint32 mask)
{
    EALLOW;
    GpioCtrlRegs.GPAMUX1.all = 0x00000000UL;
    GpioCtrlRegs.GPAMUX2.all = 0x00000000UL;
    GpioCtrlRegs.GPADIR.all = mask;
    EDIS;

    GpioDataRegs.GPASET.all = mask;
    gpio_pin_walk_delay();
    GpioDataRegs.GPATOGGLE.all = mask;
    gpio_pin_walk_delay();
    GpioDataRegs.GPACLEAR.all = mask;
    gpio_pin_walk_delay();
}

static void gpio_pin_walk_drive_b(Uint32 mask)
{
    EALLOW;
    GpioCtrlRegs.GPBMUX1.all = 0x00000000UL;
    GpioCtrlRegs.GPBDIR.all = mask;
    EDIS;

    GpioDataRegs.GPBSET.all = mask;
    gpio_pin_walk_delay();
    GpioDataRegs.GPBTOGGLE.all = mask;
    gpio_pin_walk_delay();
    GpioDataRegs.GPBCLEAR.all = mask;
    gpio_pin_walk_delay();
}

static void gpio_pin_walk_mux_pair(Uint32 low_pair, Uint32 high_pair)
{
    EALLOW;
    GpioCtrlRegs.GPAMUX1.all = low_pair;
    GpioCtrlRegs.GPAMUX2.all = high_pair;
    GpioCtrlRegs.GPBMUX1.all = (Uint32)(low_pair & 0x03FFFFFFUL);
    EDIS;
    gpio_pin_walk_delay();
}

static void gpio_pin_walk_qsel_pair(Uint32 low_pair, Uint32 high_pair)
{
    EALLOW;
    GpioCtrlRegs.GPAQSEL1.all = low_pair;
    GpioCtrlRegs.GPAQSEL2.all = high_pair;
    GpioCtrlRegs.GPBQSEL1.all = (Uint32)(low_pair & 0x03FFFFFFUL);
    EDIS;
    gpio_pin_walk_delay();
}

void main(void)
{
    Uint16 bit;

    board_demo_init();

    for (bit = 0U; bit < 32U; bit++) {
        gpio_pin_walk_drive_a((Uint32)1UL << bit);
    }

    for (bit = 0U; bit < 14U; bit++) {
        gpio_pin_walk_drive_b((Uint32)1UL << bit);
    }

    gpio_pin_walk_mux_pair(0x00000000UL, 0x00000000UL);
    gpio_pin_walk_mux_pair(0x55555555UL, 0x55555555UL);
    gpio_pin_walk_mux_pair(0xAAAAAAAAUL, 0xAAAAAAAAUL);
    gpio_pin_walk_mux_pair(0xFFFFFFFFUL, 0xFFFFFFFFUL);

    gpio_pin_walk_qsel_pair(0x00000000UL, 0x00000000UL);
    gpio_pin_walk_qsel_pair(0x55555555UL, 0x55555555UL);
    gpio_pin_walk_qsel_pair(0xAAAAAAAAUL, 0xAAAAAAAAUL);
    gpio_pin_walk_qsel_pair(0xFFFFFFFFUL, 0xFFFFFFFFUL);

    EALLOW;
    GpioCtrlRegs.GPAMUX1.all = 0x00000000UL;
    GpioCtrlRegs.GPAMUX2.all = 0x00000000UL;
    GpioCtrlRegs.GPBMUX1.all = 0x00000000UL;
    GpioCtrlRegs.GPADIR.all = 0x00000000UL;
    GpioCtrlRegs.GPBDIR.all = 0x00000000UL;
    EDIS;

    if (GpioCtrlRegs.GPAMUX1.all != 0x00000000UL) {
        test_runtime_fail(GPIO_PIN_WALK_BASIC_FAIL_GPAMUX1);
    }
    if (GpioCtrlRegs.GPAMUX2.all != 0x00000000UL) {
        test_runtime_fail(GPIO_PIN_WALK_BASIC_FAIL_GPAMUX2);
    }
    if (GpioCtrlRegs.GPBMUX1.all != 0x00000000UL) {
        test_runtime_fail(GPIO_PIN_WALK_BASIC_FAIL_GPBMUX1);
    }
    if (GpioCtrlRegs.GPADIR.all != 0x00000000UL) {
        test_runtime_fail(GPIO_PIN_WALK_BASIC_FAIL_GPADIR);
    }
    if (GpioCtrlRegs.GPBDIR.all != 0x00000000UL) {
        test_runtime_fail(GPIO_PIN_WALK_BASIC_FAIL_GPBDIR);
    }

    test_runtime_pass();
}
