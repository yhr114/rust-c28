#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

static void check_read_payload(const Uint16 *payload, Uint16 fail_base)
{
    static const Uint16 expected_read[I2C_CASE_READ_COUNT] = {
        0xDEU, 0xADU, 0xBEU, 0xEFU
    };
    Uint16 i;

    for (i = 0U; i < I2C_CASE_READ_COUNT; i++) {
        if ((payload[i] & 0x00FFU) != expected_read[i]) {
            test_runtime_fail(fail_base + ((i & 0x000FU) << 8U) + (payload[i] & 0x00FFU));
        }
    }
}

static Uint16 first_read[I2C_CASE_READ_COUNT] = {0U, 0U, 0U, 0U};
static Uint16 second_read[I2C_CASE_READ_COUNT] = {0U, 0U, 0U, 0U};

void main(void)
{
    unsigned int status;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
    if (I2C_CASE_SETTLE_US != 0UL) {
        board_delay_us(I2C_CASE_SETTLE_US);
    }

    status = i2c_case_master_read(I2C_CASE_SLAVE_ADDR,
                                  first_read,
                                  I2C_CASE_READ_COUNT,
                                  I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_FIRST_FAIL_BASE + status);
    }
    check_read_payload(first_read, I2C_CASE_DATA_FAIL_BASE);

    board_delay_us(I2C_CASE_GAP_US);

    status = i2c_case_master_read(I2C_CASE_SLAVE_ADDR,
                                  second_read,
                                  I2C_CASE_READ_COUNT,
                                  I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_SECOND_FAIL_BASE + status);
    }
    check_read_payload(second_read, I2C_CASE_DATA_FAIL_BASE + I2C_CASE_READ_COUNT);

    test_runtime_pass();
}
