// =============================================================
// eqep_polarity_test — Sweep QAP/QBP/QIP/QSP/SWAP polarity bits
// Verifies QDECCTL register read-back for all 32 polarity combos
// and QSRC mode field configuration
// =============================================================
#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

void InitEQep1Gpio(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}


Uint16 Error_number = 0;
Uint16 True_number  = 0;
Uint16 First_fail_code = 0;

#define RECORD_FAIL(code)                  \
    do {                                   \
        Error_number++;                    \
        if (First_fail_code == 0U) {       \
            First_fail_code = (code);      \
        }                                  \
    } while (0)

void main(void)
{
    Uint16 pol_cfg;
    Uint16 readback;
    Uint16 i;

    InitSysCtrl();
    InitEQep1Gpio();

    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();

    // ---------------------------------------------------------
    // Test 1: Sweep all 32 combinations of {SWAP, QSP, QIP, QBP, QAP}
    // QDECCTL bits: SWAP=bit14, QSP=bit13, QIP=bit12, QBP=bit11, QAP=bit10
    // Write each config and verify read-back
    // ---------------------------------------------------------
    for (i = 0; i < 32; i++) {
        pol_cfg = (i & 0x1F) << 10;    // Shift to bit[14:10]

        EALLOW;
        EQep1Regs.QDECCTL.all = pol_cfg;
        EDIS;

        readback = EQep1Regs.QDECCTL.all;

        // Verify polarity bits match
        if ((readback & 0x7C00) == pol_cfg) {
            True_number++;
        } else {
            RECORD_FAIL((Uint16)(EQEP_POL_FAIL_POLARITY_BASE + i));
        }
    }

    // ---------------------------------------------------------
    // Test 2: QSRC field (bits [15:14] in some variants,
    //         bits [15:14] = QSRC, or check SWAP at bit14)
    //         Verify individual bit-field read-back
    // ---------------------------------------------------------
    EALLOW;
    EQep1Regs.QDECCTL.all = 0x0000;    // All clear
    EDIS;
    if (EQep1Regs.QDECCTL.bit.QAP == 0 &&
        EQep1Regs.QDECCTL.bit.QBP == 0 &&
        EQep1Regs.QDECCTL.bit.QIP == 0 &&
        EQep1Regs.QDECCTL.bit.QSP == 0 &&
        EQep1Regs.QDECCTL.bit.SWAP == 0) {
        True_number++;
    } else {
        RECORD_FAIL(EQEP_POL_FAIL_CLEAR_BITS);
    }

    EALLOW;
    EQep1Regs.QDECCTL.bit.QAP = 1;
    EQep1Regs.QDECCTL.bit.QBP = 1;
    EQep1Regs.QDECCTL.bit.QIP = 1;
    EQep1Regs.QDECCTL.bit.QSP = 1;
    EQep1Regs.QDECCTL.bit.SWAP = 1;
    EDIS;

    if (EQep1Regs.QDECCTL.bit.QAP == 1 &&
        EQep1Regs.QDECCTL.bit.QBP == 1 &&
        EQep1Regs.QDECCTL.bit.QIP == 1 &&
        EQep1Regs.QDECCTL.bit.QSP == 1 &&
        EQep1Regs.QDECCTL.bit.SWAP == 1) {
        True_number++;
    } else {
        RECORD_FAIL(EQEP_POL_FAIL_SET_BITS);
    }

    // ---------------------------------------------------------
    // Test 3: QSRC mode field — 4 modes
    // QSRC: 00=Quadrature, 01=Direction, 10=UP count, 11=DOWN count
    // ---------------------------------------------------------
    for (i = 0; i < 4; i++) {
        Uint16 qsrc_val;
        qsrc_val = i;

        EALLOW;
        EQep1Regs.QDECCTL.bit.QSRC = qsrc_val;
        EDIS;

        if (EQep1Regs.QDECCTL.bit.QSRC == qsrc_val) {
            True_number++;
        } else {
            RECORD_FAIL((Uint16)(EQEP_POL_FAIL_QSRC_BASE + i));
        }
    }

    // ---------------------------------------------------------
    // Test 4: XCR bit (2x/4x resolution)
    // ---------------------------------------------------------
    EALLOW;
    EQep1Regs.QDECCTL.bit.XCR = 0;
    EDIS;
    if (EQep1Regs.QDECCTL.bit.XCR == 0) {
        True_number++;
    } else {
        RECORD_FAIL(EQEP_POL_FAIL_XCR_CLEAR);
    }

    EALLOW;
    EQep1Regs.QDECCTL.bit.XCR = 1;
    EDIS;
    if (EQep1Regs.QDECCTL.bit.XCR == 1) {
        True_number++;
    } else {
        RECORD_FAIL(EQEP_POL_FAIL_XCR_SET);
    }

    // ---------------------------------------------------------
    // Result: 32 sweep + 2 bitfield + 4 QSRC + 2 XCR = 40
    // ---------------------------------------------------------
    if (Error_number == 0 && True_number >= 38) {
        *(long *)0xfff0 = 0x12345678;
        pass();
    } else {
        *(long *)0xfff0 = 0x87654321;
        fail(First_fail_code == 0U ? EQEP_POL_FAIL_SUMMARY : First_fail_code);
    }

    while(1);
}
