#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    static const Uint16 payload[I2C_CASE_DATA_COUNT] = {
        0x00U, 0x11U, 0x22U, 0x33U,
        0x44U, 0x55U, 0x66U, 0x77U
    };
    unsigned int status;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
    board_delay_us(I2C_CASE_SETTLE_US);

    status = i2c_case_master_write(I2C_CASE_SLAVE_ADDR,
                                   payload,
                                   I2C_CASE_DATA_COUNT,
                                   I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_FAIL_STATUS_BASE + status);
    }

    test_runtime_pass();
}
