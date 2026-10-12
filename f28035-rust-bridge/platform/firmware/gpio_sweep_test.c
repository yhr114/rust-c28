#include "DSP28x_Project.h"

extern void rust_gpio_sweep_outputs(void);

#define GPIO_SWEEP_PIN_COUNT 45U

volatile Uint16 rust_gpio_sweep_called;
volatile Uint16 rust_gpio_sweep_pass_count;
volatile Uint16 rust_gpio_sweep_fail_count;
volatile Uint16 rust_gpio_sweep_mux[GPIO_SWEEP_PIN_COUNT];
volatile Uint16 rust_gpio_sweep_dir[GPIO_SWEEP_PIN_COUNT];
volatile Uint16 rust_gpio_sweep_data[GPIO_SWEEP_PIN_COUNT];
volatile Uint16 rust_gpio_sweep_c_low_data[GPIO_SWEEP_PIN_COUNT];
volatile Uint16 rust_gpio_sweep_c_high_data[GPIO_SWEEP_PIN_COUNT];
volatile Uint16 rust_gpio_sweep_pass[GPIO_SWEEP_PIN_COUNT];

static Uint16 gpio_mux(Uint16 pin)
{
    Uint32 mux;
    Uint16 shift;

    if (pin < 16U) {
        mux = GpioCtrlRegs.GPAMUX1.all;
        shift = (Uint16)(pin * 2U);
    } else if (pin < 32U) {
        mux = GpioCtrlRegs.GPAMUX2.all;
        shift = (Uint16)((pin - 16U) * 2U);
    } else {
        mux = GpioCtrlRegs.GPBMUX1.all;
        shift = (Uint16)((pin - 32U) * 2U);
    }

    return (Uint16)((mux >> shift) & 0x3U);
}

static Uint16 gpio_dir(Uint16 pin)
{
    if (pin < 32U) {
        return (Uint16)((GpioCtrlRegs.GPADIR.all >> pin) & 0x1U);
    }

    return (Uint16)((GpioCtrlRegs.GPBDIR.all >> (pin - 32U)) & 0x1U);
}

static Uint16 gpio_data(Uint16 pin)
{
    if (pin < 32U) {
        return (Uint16)((GpioDataRegs.GPADAT.all >> pin) & 0x1U);
    }

    return (Uint16)((GpioDataRegs.GPBDAT.all >> (pin - 32U)) & 0x1U);
}

static void gpio_drive(Uint16 pin, Uint16 high)
{
    Uint32 bit;

    if (pin < 32U) {
        bit = (Uint32)1U << pin;
        if (high != 0U) {
            GpioDataRegs.GPASET.all = bit;
        } else {
            GpioDataRegs.GPACLEAR.all = bit;
        }
    } else {
        bit = (Uint32)1U << (pin - 32U);
        if (high != 0U) {
            GpioDataRegs.GPBSET.all = bit;
        } else {
            GpioDataRegs.GPBCLEAR.all = bit;
        }
    }
}

int main(void)
{
    Uint16 pin;

    rust_gpio_sweep_outputs();

    rust_gpio_sweep_pass_count = 0U;
    rust_gpio_sweep_fail_count = 0U;

    for (pin = 0U; pin < GPIO_SWEEP_PIN_COUNT; pin++) {
        Uint16 mux = gpio_mux(pin);
        Uint16 dir = gpio_dir(pin);
        Uint16 data = gpio_data(pin);
        Uint16 c_low_data;
        Uint16 c_high_data;
        Uint16 pass;

        gpio_drive(pin, 0U);
        c_low_data = gpio_data(pin);
        gpio_drive(pin, 1U);
        c_high_data = gpio_data(pin);
        pass = (Uint16)((mux == 0U) && (dir == 1U) && (data == 1U) &&
                        (c_low_data == 0U) && (c_high_data == 1U));

        rust_gpio_sweep_mux[pin] = mux;
        rust_gpio_sweep_dir[pin] = dir;
        rust_gpio_sweep_data[pin] = data;
        rust_gpio_sweep_c_low_data[pin] = c_low_data;
        rust_gpio_sweep_c_high_data[pin] = c_high_data;
        rust_gpio_sweep_pass[pin] = pass;

        if (pass != 0U) {
            rust_gpio_sweep_pass_count++;
        } else {
            rust_gpio_sweep_fail_count++;
        }
    }

    rust_gpio_sweep_called = 1U;

    for (;;) {
    }
}
