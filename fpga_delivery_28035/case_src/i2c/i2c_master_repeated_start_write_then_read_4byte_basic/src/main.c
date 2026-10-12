#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define I2C_CASE_ARDY_CLEAR 0x0004U

static unsigned int i2c_case_master_write_no_stop(Uint16 slave_addr,
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
            return I2C_CASE_STATUS_NACK;
        }
        if ((sent < length) && (I2caRegs.I2CSTR.bit.XRDY != 0U)) {
            I2caRegs.I2CDXR = data[sent++] & 0x00FFU;
        }
        if (I2caRegs.I2CSTR.bit.ARDY != 0U) {
            I2caRegs.I2CSTR.all = I2C_CASE_ARDY_CLEAR;
            if (sent == length) {
                return I2C_CASE_STATUS_OK;
            }
        }
    }

    I2caRegs.I2CMDR.bit.STP = 1U;
    return I2C_CASE_STATUS_TIMEOUT;
}

static unsigned int i2c_case_master_read_repeated_start(Uint16 slave_addr,
                                                        Uint16 *data,
                                                        Uint16 length,
                                                        unsigned long wait_loops)
{
    Uint16 received = 0U;

    if (I2caRegs.I2CMDR.bit.STP != 0U) {
        return I2C_CASE_STATUS_STP_BUSY;
    }

    I2caRegs.I2CFFRX.all = 0x0040U;
    I2caRegs.I2CFFRX.all = 0x2040U;
    I2caRegs.I2CSAR = slave_addr;
    I2caRegs.I2CCNT = length;
    I2caRegs.I2CSTR.all = 0xFFFFU;
    I2caRegs.I2CMDR.all = I2C_CASE_MDR_FREE |
                          I2C_CASE_MDR_STT |
                          I2C_CASE_MDR_STP |
                          I2C_CASE_MDR_MST |
                          I2C_CASE_MDR_IRS;

    while (wait_loops-- != 0UL) {
        if (I2caRegs.I2CSTR.bit.ARBL != 0U) {
            I2caRegs.I2CSTR.all = 0x0001U;
            return I2C_CASE_STATUS_ARB_LOST;
        }
        if (I2caRegs.I2CSTR.bit.NACK != 0U) {
            I2caRegs.I2CSTR.all = 0x0002U;
            I2caRegs.I2CMDR.bit.STP = 1U;
            return I2C_CASE_STATUS_NACK;
        }
        if ((received < length) && (I2caRegs.I2CSTR.bit.RRDY != 0U)) {
            data[received] = I2caRegs.I2CDRR & 0x00FFU;
            received++;
            if (i2c_case_clear_rrdy_and_wait_low(&wait_loops) != I2C_CASE_STATUS_OK) {
                return I2C_CASE_STATUS_TIMEOUT;
            }
        }
        if (I2caRegs.I2CSTR.bit.SCD != 0U) {
            if ((received < length) && (I2caRegs.I2CSTR.bit.RRDY != 0U)) {
                data[received] = I2caRegs.I2CDRR & 0x00FFU;
                received++;
                if (i2c_case_clear_rrdy_and_wait_low(&wait_loops) != I2C_CASE_STATUS_OK) {
                    return I2C_CASE_STATUS_TIMEOUT;
                }
            }
            I2caRegs.I2CSTR.all = 0x0020U;
            if (received == length) {
                return I2C_CASE_STATUS_OK;
            }
            return I2C_CASE_STATUS_TIMEOUT;
        }
    }

    I2caRegs.I2CMDR.bit.STP = 1U;
    return I2C_CASE_STATUS_TIMEOUT;
}

void main(void)
{
    static const Uint16 write_payload[I2C_CASE_DATA_COUNT] = {
        0xDEU, 0xADU, 0xBEU, 0xEFU
    };
    Uint16 read_payload[I2C_CASE_DATA_COUNT] = {0U, 0U, 0U, 0U};
    unsigned int status;
    Uint16 i;

    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
#if I2C_CASE_SETTLE_US > 0
    board_delay_us(I2C_CASE_SETTLE_US);
#endif

    status = i2c_case_master_write_no_stop(I2C_CASE_SLAVE_ADDR,
                                           write_payload,
                                           I2C_CASE_DATA_COUNT,
                                           I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_WRITE_FAIL_BASE + status);
    }

    status = i2c_case_master_read_repeated_start(I2C_CASE_SLAVE_ADDR,
                                                 read_payload,
                                                 I2C_CASE_DATA_COUNT,
                                                 I2C_CASE_WAIT_LOOPS);
    if (status != I2C_CASE_STATUS_OK) {
        test_runtime_fail(I2C_CASE_READ_FAIL_BASE + status);
    }

    for (i = 0U; i < I2C_CASE_DATA_COUNT; i++) {
        if ((read_payload[i] & 0x00FFU) != write_payload[i]) {
            test_runtime_fail(I2C_CASE_DATA_FAIL_BASE + i);
        }
    }

    test_runtime_pass();
}
