#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    static const Uint16 first_payload[I2C_CASE_FIRST_DATA_COUNT] = {
        0xA5U, 0x5AU, 0x3CU, 0xC3U
    };
    static const Uint16 second_payload[I2C_CASE_SECOND_DATA_COUNT] = {
        0x10U, 0x20U, 0x30U, 0x40U, 0x50U, 0x60U
    };
    unsigned int status;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
    board_delay_us(I2C_CASE_SETTLE_US);

    status = i2c_case_master_write(I2C_CASE_SLAVE_ADDR,
                                   first_payload,
                                   I2C_CASE_FIRST_DATA_COUNT,
                                   I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_FIRST_FAIL_BASE + status);
    }

    board_delay_us(I2C_CASE_GAP_US);

    status = i2c_case_master_write(I2C_CASE_SLAVE_ADDR,
                                   second_payload,
                                   I2C_CASE_SECOND_DATA_COUNT,
                                   I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_SECOND_FAIL_BASE + status);
    }

    test_runtime_pass();
}
