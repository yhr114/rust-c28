#include "board_sci_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_SCICCR  0x580001UL
#define FAIL_CTL1    0x580002UL
#define FAIL_BAUD    0x580003UL
#define FAIL_CTL2    0x580004UL
#define FAIL_FFTX    0x580005UL
#define FAIL_FFRX    0x580006UL
#define FAIL_FFCT    0x580007UL
#define FAIL_PRI     0x580008UL

void main(void)
{
    unsigned short rd;

    device_sdk_init();

    EALLOW;
    sci_reg_write16(SCI_REG_SCICCR, (unsigned short)(SCICCR_LOOPB_MASK | SCICCR_PARITY_EN_MASK | 0x0005U));
    sci_reg_write16(SCI_REG_SCICTL1, (unsigned short)(SCICTL1_RXERR_INTEN_MASK | SCICTL1_TXENA_MASK | SCICTL1_RXENA_MASK));
    sci_reg_write16(SCI_REG_SCICTL2, (unsigned short)(SCICTL2_RXBK_INTEN_MASK | SCICTL2_TX_INTEN_MASK));
    sci_reg_write16(SCI_REG_SCIHBAUD, 0x0012U);
    sci_reg_write16(SCI_REG_SCILBAUD, 0x0034U);
    sci_reg_write16(SCI_REG_SCIFFTX, (unsigned short)(SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFINTENA_MASK | 0x0003U));
    sci_reg_write16(SCI_REG_SCIFFRX, (unsigned short)(SCIFFRX_FFINTENA_MASK | 0x0004U));
    sci_reg_write16(SCI_REG_SCIFFCT, (unsigned short)(SCIFFCT_CDC_MASK | 0x0055U));
    sci_reg_write16(SCI_REG_SCIPRI, 0x0010U);
    EDIS;

    rd = sci_reg_read16(SCI_REG_SCICCR);
    if ((rd & (SCICCR_LOOPB_MASK | SCICCR_PARITY_EN_MASK | SCICCR_CHAR_MASK)) !=
        (unsigned short)(SCICCR_LOOPB_MASK | SCICCR_PARITY_EN_MASK | 0x0005U)) {
        test_runtime_fail(FAIL_SCICCR + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCICTL1);
    if ((rd & (SCICTL1_RXERR_INTEN_MASK | SCICTL1_TXENA_MASK | SCICTL1_RXENA_MASK)) !=
        (unsigned short)(SCICTL1_RXERR_INTEN_MASK | SCICTL1_TXENA_MASK | SCICTL1_RXENA_MASK)) {
        test_runtime_fail(FAIL_CTL1 + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCIHBAUD);
    if ((rd & 0x00FFU) != 0x0012U) {
        test_runtime_fail(FAIL_BAUD + (unsigned long)rd);
    }
    rd = sci_reg_read16(SCI_REG_SCILBAUD);
    if ((rd & 0x00FFU) != 0x0034U) {
        test_runtime_fail(FAIL_BAUD + 0x100UL + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCICTL2);
    if ((rd & (SCICTL2_RXBK_INTEN_MASK | SCICTL2_TX_INTEN_MASK)) !=
        (unsigned short)(SCICTL2_RXBK_INTEN_MASK | SCICTL2_TX_INTEN_MASK)) {
        test_runtime_fail(FAIL_CTL2 + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCIFFTX);
    if ((rd & (SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFINTENA_MASK | SCIFFTX_FFIL_MASK)) !=
        (unsigned short)(SCIFFTX_SCIRSTN_MASK | SCIFFTX_FFINTENA_MASK | 0x0003U)) {
        test_runtime_fail(FAIL_FFTX + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCIFFRX);
    if ((rd & (SCIFFRX_FFINTENA_MASK | SCIFFRX_FFIL_MASK)) !=
        (unsigned short)(SCIFFRX_FFINTENA_MASK | 0x0004U)) {
        test_runtime_fail(FAIL_FFRX + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCIFFCT);
    if ((rd & (SCIFFCT_CDC_MASK | SCIFFCT_FFTXDLY_MASK)) !=
        (unsigned short)(SCIFFCT_CDC_MASK | 0x0055U)) {
        test_runtime_fail(FAIL_FFCT + (unsigned long)rd);
    }

    rd = sci_reg_read16(SCI_REG_SCIPRI);
    if ((rd & SCIPRI_SUSP_MASK) != 0x0010U) {
        test_runtime_fail(FAIL_PRI + (unsigned long)rd);
    }

    test_runtime_pass();
}

