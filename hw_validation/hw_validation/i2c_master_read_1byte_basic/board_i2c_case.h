#ifndef BOARD_I2C_CASE_H
#define BOARD_I2C_CASE_H
#include "DSP28x_Project.h"
/* Local adapter status encoding; 6 is reserved by the original main.c. */
#define I2C_CASE_STATUS_OK 0U
#define I2C_CASE_STATUS_TIMEOUT 1U
#define I2C_CASE_STATUS_STP_BUSY 2U
#define I2C_CASE_STATUS_BUS_BUSY 3U
#define I2C_CASE_STATUS_ARB_LOST 4U
#define I2C_CASE_STATUS_NACK 5U
#define I2C_CASE_MDR_FREE 0x4000U
#define I2C_CASE_MDR_STT 0x2000U
#define I2C_CASE_MDR_STP 0x0800U
#define I2C_CASE_MDR_MST 0x0400U
#define I2C_CASE_MDR_TRX 0x0200U
#define I2C_CASE_MDR_IRS 0x0020U
void board_demo_init(void);
void board_delay_us(unsigned long us);
void i2c_case_i2ca_init(Uint16 own, Uint16 prescaler, Uint16 low, Uint16 high);
unsigned int i2c_case_master_read(Uint16 address, Uint16 *data, Uint16 length, unsigned long wait_loops);
#endif

