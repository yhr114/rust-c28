#include "board_i2c_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define I2C_CASE_REG16(addr) (*(volatile Uint16 *)(addr))

static volatile Uint16 i2c_case_sink;

static void i2c_case_touch(Uint16 value)
{
    i2c_case_sink ^= value;
}

static void i2c_case_expect_mask(Uint16 actual,
                                 Uint16 expected,
                                 Uint16 mask,
                                 Uint16 fail_code)
{
    if ((actual & mask) != (expected & mask)) {
        test_runtime_fail(I2C_CASE_FAIL_BASE + fail_code);
    }
    i2c_case_touch(actual);
}

void main(void)
{
    board_demo_init();

    i2c_case_i2ca_init(I2C_CASE_OWN_ADDR,
                       I2C_CASE_PRESCALER,
                       I2C_CASE_CLK_LOW,
                       I2C_CASE_CLK_HIGH);
#if I2C_CASE_SETTLE_US > 0
    board_delay_us(I2C_CASE_SETTLE_US);
#endif

    I2caRegs.I2COAR = 0x0035U;
    i2c_case_expect_mask(I2caRegs.I2COAR, 0x0035U, 0x03FFU, 0x01U);

    I2caRegs.I2CIER.all = 0x0055U;
    i2c_case_expect_mask(I2caRegs.I2CIER.all, 0x0055U, 0x007FU, 0x02U);

    I2caRegs.I2CCLKL = 0x00C8U;
    i2c_case_expect_mask(I2caRegs.I2CCLKL, 0x00C8U, 0xFFFFU, 0x03U);

    I2caRegs.I2CCLKH = 0x00A0U;
    i2c_case_expect_mask(I2caRegs.I2CCLKH, 0x00A0U, 0xFFFFU, 0x04U);

    I2caRegs.I2CCNT = 0x0004U;
    i2c_case_expect_mask(I2caRegs.I2CCNT, 0x0004U, 0xFFFFU, 0x05U);

    i2c_case_touch(I2caRegs.I2CDRR & 0x00FFU);

    I2caRegs.I2CSAR = 0x0036U;
    i2c_case_expect_mask(I2caRegs.I2CSAR, 0x0036U, 0x03FFU, 0x07U);

    I2caRegs.I2CDXR = 0x00A5U;
    i2c_case_expect_mask(I2caRegs.I2CDXR, 0x00A5U, 0x00FFU, 0x08U);

    I2caRegs.I2CMDR.all = I2C_CASE_MDR_IRS;
    i2c_case_expect_mask(I2caRegs.I2CMDR.all, I2C_CASE_MDR_IRS, I2C_CASE_MDR_IRS, 0x09U);

    i2c_case_touch(I2C_CASE_REG16(0x790AU));
    i2c_case_touch(I2C_CASE_REG16(0x790BU));

    I2caRegs.I2CPSC.all = 0x0006U;
    i2c_case_expect_mask(I2caRegs.I2CPSC.all, 0x0006U, 0x00FFU, 0x0CU);

    i2c_case_expect_mask(I2C_CASE_REG16(0x790DU), 0x0105U, 0xFFFFU, 0x0DU);
    i2c_case_expect_mask(I2C_CASE_REG16(0x790EU), 0x0005U, 0xFFFFU, 0x0EU);

    I2caRegs.I2CFFTX.all = 0x6000U;
    i2c_case_expect_mask(I2caRegs.I2CFFTX.all, 0x6000U, 0x6000U, 0x20U);

    I2caRegs.I2CFFRX.all = 0x2040U;
    i2c_case_expect_mask(I2caRegs.I2CFFRX.all, 0x2000U, 0x2000U, 0x21U);

    I2caRegs.I2CSTR.all = 0xFFFFU;
    i2c_case_touch(I2caRegs.I2CSTR.all);

    if (i2c_case_sink == 0xFFFFU) {
        test_runtime_fail(I2C_CASE_FAIL_BASE + 0x40U);
    }

    test_runtime_pass();
}
