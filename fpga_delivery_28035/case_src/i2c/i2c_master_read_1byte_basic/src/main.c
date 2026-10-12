#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

void main(void)
{
    static const Uint16 expected_read[I2C_CASE_DATA_COUNT] = {
        0xDEU
    };
    Uint16 read_payload[I2C_CASE_DATA_COUNT] = {0U};
    unsigned int status;
    Uint16 i;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
    board_delay_us(I2C_CASE_SETTLE_US);

    status = i2c_case_master_read(I2C_CASE_SLAVE_ADDR,
                                  read_payload,
                                  I2C_CASE_DATA_COUNT,
                                  I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_READ_FAIL_BASE + status);
    }

    for (i = 0U; i < I2C_CASE_DATA_COUNT; i++) {
        if ((read_payload[i] & 0x00FFU) != expected_read[i]) {
            test_runtime_fail(I2C_CASE_DATA_FAIL_BASE + i);
        }
    }

    test_runtime_pass();
}
