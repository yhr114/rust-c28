#include "board_lin_case.h"
#include "case_config.h"
#include "test_runtime.h"

#define FAIL_READBACK 0x4C5201UL
#define FAIL_GCR2     0x4C5202UL
#define FAIL_BRSR     0x4C5203UL
#define FAIL_MBRSR    0x4C5204UL
#define FAIL_FORMAT   0x4C5205UL
#define FAIL_COMP     0x4C5206UL
#define FAIL_MASK     0x4C5207UL
#define FAIL_ID       0x4C5208UL

void main(void)
{
    device_sdk_init();
    lin_case_gpio9_11_mux_init();
    lin_case_basic_slave_init();

    if (lin_case_readback_ok() == 0U) {
        test_runtime_fail(FAIL_READBACK);
    }

    if (LinaRegs.SCIGCR2.bit.CC != 1U) {
        test_runtime_fail(FAIL_GCR2 + (unsigned long)LinaRegs.SCIGCR2.all);
    }
    if (LinaRegs.BRSR.bit.SCI_LIN_PSL != 96U || LinaRegs.BRSR.bit.M != 11U) {
        test_runtime_fail(FAIL_BRSR + (unsigned long)LinaRegs.BRSR.all);
    }
    if ((LinaRegs.MBRSR & 0x00FFU) != 92U) {
        test_runtime_fail(FAIL_MBRSR + (unsigned long)LinaRegs.MBRSR);
    }
    if ((LinaRegs.SCIFORMAT.bit.LENGTH & 0x7U) != 0U) {
        test_runtime_fail(FAIL_FORMAT + (unsigned long)LinaRegs.SCIFORMAT.all);
    }
    if (LinaRegs.LINCOMP.bit.SBREAK != 5U || LinaRegs.LINCOMP.bit.SDEL != 3U) {
        test_runtime_fail(FAIL_COMP + (unsigned long)LinaRegs.LINCOMP.all);
    }
    if (LinaRegs.LINMASK.bit.TXIDMASK != 0xFFU || LinaRegs.LINMASK.bit.RXIDMASK != 0xFFU) {
        test_runtime_fail(FAIL_MASK + (unsigned long)LinaRegs.LINMASK.all);
    }
    if (LinaRegs.LINID.bit.IDSLAVETASKBYTE != 0x10U) {
        test_runtime_fail(FAIL_ID + (unsigned long)LinaRegs.LINID.all);
    }

    test_runtime_pass();
}

