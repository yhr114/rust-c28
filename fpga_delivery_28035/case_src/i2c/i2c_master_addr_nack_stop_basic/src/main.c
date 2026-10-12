#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define I2C_CASE_STATUS_UNEXPECTED_ACK 6U

static unsigned int i2c_case_wait_for_stop(unsigned long wait_loops)
{
    while (wait_loops-- != 0UL) {
        if (I2caRegs.I2CSTR.bit.SCD != 0U) {
            I2caRegs.I2CSTR.all = 0x0020U;
            return I2C_CASE_STATUS_OK;
        }
        if ((I2caRegs.I2CMDR.bit.STP == 0U) && (I2caRegs.I2CSTR.bit.BB == 0U)) {
            return I2C_CASE_STATUS_OK;
        }
    }
    return I2C_CASE_STATUS_TIMEOUT;
}

static unsigned int i2c_case_master_write_expect_nack(Uint16 slave_addr,
                                                       const Uint16 *data,
                                                       Uint16 length,
                                                       unsigned long wait_loops)
{
    Uint16 sent = 0U;

    if (I2caRegs.I2CMDR.bit.STP != 0U) {
        return I2C_CASE_STATUS_STP_BUSY;
    }
    if (I2caRegs.I2CSTR.bit.BB != 0U) {
        return I2C_CASE_STATUS_BUS_BUSY;
    }

    I2caRegs.I2CSAR = slave_addr;
    I2caRegs.I2CCNT = length;
    I2caRegs.I2CSTR.all = 0xFFFFU;

    if (length != 0U) {
        I2caRegs.I2CDXR = data[sent++] & 0x00FFU;
    }

    I2caRegs.I2CMDR.all = I2C_CASE_MDR_FREE |
                          I2C_CASE_MDR_STT |
                          I2C_CASE_MDR_STP |
                          I2C_CASE_MDR_MST |
                          I2C_CASE_MDR_TRX |
                          I2C_CASE_MDR_IRS;

    while (wait_loops-- != 0UL) {
        if (I2caRegs.I2CSTR.bit.ARBL != 0U) {
            I2caRegs.I2CSTR.all = 0x0001U;
            return I2C_CASE_STATUS_ARB_LOST;
        }
        if (I2caRegs.I2CSTR.bit.NACK != 0U) {
            I2caRegs.I2CSTR.all = 0x0002U;
            I2caRegs.I2CMDR.bit.STP = 1U;
            return i2c_case_wait_for_stop(wait_loops);
        }
        if ((sent < length) && (I2caRegs.I2CSTR.bit.XRDY != 0U)) {
            I2caRegs.I2CDXR = data[sent++] & 0x00FFU;
        }
        if (I2caRegs.I2CSTR.bit.SCD != 0U) {
            I2caRegs.I2CSTR.all = 0x0020U;
            return I2C_CASE_STATUS_UNEXPECTED_ACK;
        }
    }

    I2caRegs.I2CMDR.bit.STP = 1U;
    return I2C_CASE_STATUS_TIMEOUT;
}

void main(void)
{
    static const Uint16 payload[I2C_CASE_DATA_COUNT] = {
        0x3CU
    };
    unsigned int status;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
#if I2C_CASE_SETTLE_US > 0
    board_delay_us(I2C_CASE_SETTLE_US);
#endif

    status = i2c_case_master_write_expect_nack(I2C_CASE_SLAVE_ADDR,
                                               payload,
                                               I2C_CASE_DATA_COUNT,
                                               I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_FAIL_STATUS_BASE + status);
    }

    test_runtime_pass();
}
