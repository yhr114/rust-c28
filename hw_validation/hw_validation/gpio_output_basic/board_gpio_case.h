#ifndef BOARD_GPIO_CASE_H
#define BOARD_GPIO_CASE_H
#include "DSP28x_Project.h"
void board_demo_init(void);
void gpio_case_gpio34_output_init(unsigned int level);
void gpio_case_gpio34_toggle(void);
void gpio_case_gpio34_write(unsigned int level);
unsigned int gpio_case_gpio34_read(void);
void board_delay_us(unsigned long us);
#endif

