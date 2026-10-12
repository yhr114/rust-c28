#include "DSP28x_Project.h"
#include "case_config.h"
#include "test_runtime.h"

#define pass() test_runtime_pass()
#define fail(code) test_runtime_fail((code))
#define exit() test_runtime_exit()
#define uvm_pass() test_runtime_pass()

static Uint16 Error_number;
static Uint16 True_number;
static Uint16 First_fail_code;

static void InitEQep1Gpio(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EQEP1ENCLK = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO20 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO21 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO22 = 1U;
    GpioCtrlRegs.GPAMUX2.bit.GPIO23 = 1U;
    EDIS;
}

#define CHECK_ID(code, cond)                \
    do {                                    \
        if (cond) {                         \
            True_number++;                  \
        } else {                            \
            Error_number++;                 \
            if (First_fail_code == 0U) {    \
                First_fail_code = (code);   \
            }                               \
        }                                   \
    } while (0)

static void run_internal_counter_write_cov(void)
{
    EALLOW;
    EQep1Regs.QEPCTL.bit.QPEN = 1U;
    EQep1Regs.QEPCTL.bit.WDE = 0U;
    EQep1Regs.QCAPCTL.bit.CEN = 0U;

    EQep1Regs.QWDTMR = 0x00FFU;
    CHECK_ID(EQEP_REG_FAIL_QWDTMR, EQep1Regs.QWDTMR == 0x00FFU);
    EQep1Regs.QWDTMR = 0xFF00U;
    CHECK_ID(EQEP_REG_FAIL_QWDTMR, EQep1Regs.QWDTMR == 0xFF00U);

    EQep1Regs.QCTMR = 0x55AAU;
    CHECK_ID(EQEP_REG_FAIL_QCTMR, EQep1Regs.QCTMR == 0x55AAU);
    EQep1Regs.QCTMR = 0xAA55U;
    CHECK_ID(EQEP_REG_FAIL_QCTMR, EQep1Regs.QCTMR == 0xAA55U);

    EQep1Regs.QCPRD = 0x55AAU;
    CHECK_ID(EQEP_REG_FAIL_QCPRD, EQep1Regs.QCPRD == 0x55AAU);
    EQep1Regs.QCPRD = 0xAA55U;
    CHECK_ID(EQEP_REG_FAIL_QCPRD, EQep1Regs.QCPRD == 0xAA55U);

    EQep1Regs.QEPSTS.all = 0x008EU;
    CHECK_ID(EQEP_REG_FAIL_QEPSTS_CLEAR,
             (EQep1Regs.QEPSTS.all & 0x008EU) == 0U);

    EQep1Regs.QCAPCTL.bit.CEN = 0U;
    EQep1Regs.QEPCTL.bit.WDE = 0U;
    EQep1Regs.QEPCTL.bit.QPEN = 0U;
    EDIS;
}

void main(void)
{
    InitSysCtrl();
    InitEQep1Gpio();

    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();

    EALLOW;
    EQep1Regs.QDECCTL.all = 0x0000;
    EQep1Regs.QEPCTL.all  = 0x0000;
    EQep1Regs.QCAPCTL.all = 0x0000;
    EQep1Regs.QPOSCTL.all = 0x0000;
    EQep1Regs.QEINT.all   = 0x0000;
    EDIS;

    EALLOW;
    EQep1Regs.QDECCTL.bit.QSRC  = 0x3U;
    EQep1Regs.QDECCTL.bit.XCR   = 1U;
    EQep1Regs.QDECCTL.bit.SWAP  = 1U;
    EQep1Regs.QDECCTL.bit.IGATE = 1U;
    EQep1Regs.QDECCTL.bit.QAP   = 1U;
    EQep1Regs.QDECCTL.bit.QBP   = 1U;
    EQep1Regs.QDECCTL.bit.QIP   = 1U;
    EQep1Regs.QDECCTL.bit.QSP   = 1U;
    EDIS;

    CHECK_ID(EQEP_REG_FAIL_QDEC_QSRC,  EQep1Regs.QDECCTL.bit.QSRC == 3U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_XCR,   EQep1Regs.QDECCTL.bit.XCR == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_SWAP,  EQep1Regs.QDECCTL.bit.SWAP == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_IGATE, EQep1Regs.QDECCTL.bit.IGATE == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_QAP,   EQep1Regs.QDECCTL.bit.QAP == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_QBP,   EQep1Regs.QDECCTL.bit.QBP == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_QIP,   EQep1Regs.QDECCTL.bit.QIP == 1U);
    CHECK_ID(EQEP_REG_FAIL_QDEC_QSP,   EQep1Regs.QDECCTL.bit.QSP == 1U);

    EALLOW;
    EQep1Regs.QEPCTL.bit.FREE_SOFT = 2U;
    EQep1Regs.QEPCTL.bit.PCRM      = 1U;
    EQep1Regs.QEPCTL.bit.QCLM      = 1U;
    EQep1Regs.QEPCTL.bit.IEL       = 1U;
    EQep1Regs.QEPCTL.bit.SEL       = 1U;
    EDIS;

    CHECK_ID(EQEP_REG_FAIL_QEP_FREE_SOFT,  EQep1Regs.QEPCTL.bit.FREE_SOFT == 2U);
    CHECK_ID(EQEP_REG_FAIL_QEP_PCRM,       EQep1Regs.QEPCTL.bit.PCRM == 1U);
    CHECK_ID(EQEP_REG_FAIL_QEP_QCLM,       EQep1Regs.QEPCTL.bit.QCLM == 1U);
    CHECK_ID(EQEP_REG_FAIL_QEP_IEL,        EQep1Regs.QEPCTL.bit.IEL == 1U);
    CHECK_ID(EQEP_REG_FAIL_QEP_SEL,        EQep1Regs.QEPCTL.bit.SEL == 1U);
    CHECK_ID(EQEP_REG_FAIL_QEP_UTE_RESET,  EQep1Regs.QEPCTL.bit.UTE == 0U);
    CHECK_ID(EQEP_REG_FAIL_QEP_WDE_RESET,  EQep1Regs.QEPCTL.bit.WDE == 0U);
    CHECK_ID(EQEP_REG_FAIL_QEP_QPEN_RESET, EQep1Regs.QEPCTL.bit.QPEN == 0U);

    EALLOW;
    EQep1Regs.QCAPCTL.bit.CCPS = 5U;
    EQep1Regs.QCAPCTL.bit.UPPS = 9U;
    EQep1Regs.QPOSCTL.bit.PCE    = 1U;
    EQep1Regs.QPOSCTL.bit.PCPOL  = 1U;
    EQep1Regs.QPOSCTL.bit.PCLOAD = 1U;
    EQep1Regs.QPOSCTL.bit.PCSHDW = 0U;
    EDIS;

    CHECK_ID(EQEP_REG_FAIL_QCAP_CEN_RESET, EQep1Regs.QCAPCTL.bit.CEN == 0U);
    CHECK_ID(EQEP_REG_FAIL_QCAP_CCPS,      EQep1Regs.QCAPCTL.bit.CCPS == 5U);
    CHECK_ID(EQEP_REG_FAIL_QCAP_UPPS,      EQep1Regs.QCAPCTL.bit.UPPS == 9U);
    CHECK_ID(EQEP_REG_FAIL_QPOS_PCE,       EQep1Regs.QPOSCTL.bit.PCE == 1U);
    CHECK_ID(EQEP_REG_FAIL_QPOS_PCPOL,     EQep1Regs.QPOSCTL.bit.PCPOL == 1U);
    CHECK_ID(EQEP_REG_FAIL_QPOS_PCLOAD,    EQep1Regs.QPOSCTL.bit.PCLOAD == 1U);
    CHECK_ID(EQEP_REG_FAIL_QPOS_PCSHDW,    EQep1Regs.QPOSCTL.bit.PCSHDW == 0U);

    EQep1Regs.QPOSINIT = 0x12345678UL;
    EQep1Regs.QPOSMAX  = 0x89ABCDEFUL;
    EQep1Regs.QPOSCMP  = 0x00001234UL;
    EQep1Regs.QUPRD    = 0x00023456UL;
    EQep1Regs.QWDPRD   = 0x3456U;

    CHECK_ID(EQEP_REG_FAIL_QPOSINIT, EQep1Regs.QPOSINIT == 0x12345678UL);
    CHECK_ID(EQEP_REG_FAIL_QPOSMAX,  EQep1Regs.QPOSMAX  == 0x89ABCDEFUL);
    CHECK_ID(EQEP_REG_FAIL_QPOSCMP,  EQep1Regs.QPOSCMP  == 0x00001234UL);
    CHECK_ID(EQEP_REG_FAIL_QUPRD,    EQep1Regs.QUPRD    == 0x00023456UL);
    CHECK_ID(EQEP_REG_FAIL_QWDPRD,   EQep1Regs.QWDPRD   == 0x3456U);

    run_internal_counter_write_cov();

    EQep1Regs.QEINT.all = 0x0FFE;
    CHECK_ID(EQEP_REG_FAIL_QEINT, (EQep1Regs.QEINT.all & 0x0FFE) == 0x0FFE);

    if (Error_number == 0U && True_number >= 29U) {
        pass();
    } else {
        fail(First_fail_code == 0U ? EQEP_REG_FAIL_SUMMARY : First_fail_code);
    }

    while (1) {
    }
}
