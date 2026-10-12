#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "epwm_reg_rw_smoke only supports VERSION=28035"
#endif

#include "device_28035.h"

volatile Uint16 g_reset_tbctl;
volatile Uint16 g_reset_tbctr;
volatile Uint16 g_reset_tbprd;
volatile Uint16 g_reset_cmpa;
volatile Uint16 g_reset_aqctla;
volatile Uint16 g_reset_aqctlb;
volatile Uint16 g_reset_dbctl;
volatile Uint16 g_reset_dbred;
volatile Uint16 g_reset_dbfed;
volatile Uint16 g_reset_etsel;
volatile Uint16 g_reset_etps;
volatile Uint16 g_reset_tbphshr;
volatile Uint16 g_reset_tbprdhr;
volatile Uint16 g_reset_cmpahr;
volatile Uint16 g_reset_hrcnfg;
volatile Uint16 g_reset_hrpwr;
volatile Uint16 g_reset_hrpctl;

volatile Uint16 g_tbprd_readback_5555;
volatile Uint16 g_tbprd_readback_aaaa;
volatile Uint16 g_cmpa_readback_5555;
volatile Uint16 g_cmpa_readback_aaaa;
volatile Uint16 g_aqctla_readback_5555;
volatile Uint16 g_aqctla_readback_aaaa;
volatile Uint16 g_aqctlb_readback_5555;
volatile Uint16 g_aqctlb_readback_aaaa;
volatile Uint16 g_dbctl_readback_5555;
volatile Uint16 g_dbctl_readback_aaaa;
volatile Uint16 g_dbred_readback_5555;
volatile Uint16 g_dbred_readback_aaaa;
volatile Uint16 g_dbfed_readback_5555;
volatile Uint16 g_dbfed_readback_aaaa;
volatile Uint16 g_etsel_readback_5555;
volatile Uint16 g_etsel_readback_aaaa;
volatile Uint16 g_tbphshr_readback_5555;
volatile Uint16 g_tbphshr_readback_aaaa;
volatile Uint16 g_tbprdhr_readback_5555;
volatile Uint16 g_tbprdhr_readback_aaaa;
volatile Uint16 g_cmpahr_readback_5555;
volatile Uint16 g_cmpahr_readback_aaaa;
volatile Uint16 g_hrcnfg_readback_5555;
volatile Uint16 g_hrcnfg_readback_aaaa;
volatile Uint16 g_hrpwr_readback_5555;
volatile Uint16 g_hrpwr_readback_aaaa;
volatile Uint16 g_hrpctl_readback_5555;
volatile Uint16 g_hrpctl_readback_aaaa;
volatile Uint16 g_tbprdhrm_alias_readback;
volatile Uint16 g_cmpahrm_alias_readback;
volatile Uint16 g_hrcnfg_pack32_readback;
volatile Uint16 g_hrpwr_pack32_readback;

static void epwm_init_case(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR1.bit.EPWM1ENCLK = 1U;
    EDIS;
}

static void capture_reset_snapshot(void)
{
    g_reset_tbctl = EPwm1Regs.TBCTL.all;
    g_reset_tbctr = EPwm1Regs.TBCTR;
    g_reset_tbprd = EPwm1Regs.TBPRD;
    g_reset_cmpa = EPwm1Regs.CMPA.half.CMPA;
    g_reset_aqctla = EPwm1Regs.AQCTLA.all;
    g_reset_aqctlb = EPwm1Regs.AQCTLB.all;
    g_reset_dbctl = EPwm1Regs.DBCTL.all;
    g_reset_dbred = EPwm1Regs.DBRED;
    g_reset_dbfed = EPwm1Regs.DBFED;
    g_reset_etsel = EPwm1Regs.ETSEL.all;
    g_reset_etps = EPwm1Regs.ETPS.all;
    g_reset_tbphshr = EPwm1Regs.TBPHS.half.TBPHSHR;
    g_reset_tbprdhr = EPwm1Regs.TBPRDHR;
    g_reset_cmpahr = EPwm1Regs.CMPA.half.CMPAHR;
    g_reset_hrcnfg = EPwm1Regs.HRCNFG.all;
    g_reset_hrpwr = EPwm1Regs.HRPWR.all;
    g_reset_hrpctl = EPwm1Regs.HRPCTL.all;
}

static void prepare_rw_phase(void)
{
    EALLOW;
    EPwm1Regs.TBCTL.all = EPWM_REG_RW_RESET_TBCTL;
    EPwm1Regs.TBCTR = 0U;
    EPwm1Regs.TBPRD = 0U;
    EPwm1Regs.CMPA.half.CMPA = 0U;
    EPwm1Regs.AQCTLA.all = 0U;
    EPwm1Regs.AQCTLB.all = 0U;
    EPwm1Regs.DBCTL.all = 0U;
    EPwm1Regs.DBRED = 0U;
    EPwm1Regs.DBFED = 0U;
    EPwm1Regs.ETSEL.all = 0U;
    EPwm1Regs.ETPS.all = 0U;
    EPwm1Regs.TBPHS.half.TBPHSHR = 0U;
    EPwm1Regs.TBPRDHR = 0U;
    EPwm1Regs.CMPA.half.CMPAHR = 0U;
    EPwm1Regs.HRCNFG.all = 0U;
    EPwm1Regs.HRPWR.all = 0U;
    EPwm1Regs.HRPCTL.all = 0U;
    EDIS;
}

static void check_reset_values(void)
{
    if (g_reset_tbctl != EPWM_REG_RW_RESET_TBCTL) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_TBCTL);
    }
    if (g_reset_tbctr != EPWM_REG_RW_RESET_TBCTR) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_TBCTR);
    }
    if (g_reset_tbprd != EPWM_REG_RW_RESET_TBPRD) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_TBPRD);
    }
    if (g_reset_cmpa != EPWM_REG_RW_RESET_CMPA) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_CMPA);
    }
    if (g_reset_aqctla != EPWM_REG_RW_RESET_AQCTLA) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_AQCTLA);
    }
    if (g_reset_aqctlb != EPWM_REG_RW_RESET_AQCTLB) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_AQCTLB);
    }
    if (g_reset_dbctl != EPWM_REG_RW_RESET_DBCTL) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_DBCTL);
    }
    if (g_reset_dbred != EPWM_REG_RW_RESET_DBRED) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_DBRED);
    }
    if (g_reset_dbfed != EPWM_REG_RW_RESET_DBFED) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_DBFED);
    }
    if (g_reset_etsel != EPWM_REG_RW_RESET_ETSEL) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_ETSEL);
    }
    if (g_reset_etps != EPWM_REG_RW_RESET_ETPS) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_ETPS);
    }
    if (g_reset_tbphshr != EPWM_REG_RW_RESET_TBPHSHR) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_TBPHSHR);
    }
    if (g_reset_tbprdhr != EPWM_REG_RW_RESET_TBPRDHR) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_TBPRDHR);
    }
    if (g_reset_cmpahr != EPWM_REG_RW_RESET_CMPAHR) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_CMPAHR);
    }
    if (g_reset_hrcnfg != EPWM_REG_RW_RESET_HRCNFG) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_HRCNFG);
    }
    if (g_reset_hrpwr != EPWM_REG_RW_RESET_HRPWR) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_HRPWR);
    }
    if (g_reset_hrpctl != EPWM_REG_RW_RESET_HRPCTL) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RESET_HRPCTL);
    }
}

static void check_tbprd_rw_masked(void)
{
    EPwm1Regs.TBPRD = EPWM_REG_RW_WRITE_5555_16;
    g_tbprd_readback_5555 = EPwm1Regs.TBPRD;
    if (g_tbprd_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_TBPRD)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPRD_5555);
    }

    EPwm1Regs.TBPRD = EPWM_REG_RW_WRITE_AAAA_16;
    g_tbprd_readback_aaaa = EPwm1Regs.TBPRD;
    if (g_tbprd_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_TBPRD)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPRD_AAAA);
    }
}

static void check_cmpa_rw_masked(void)
{
    EPwm1Regs.CMPA.half.CMPA = EPWM_REG_RW_WRITE_5555_16;
    g_cmpa_readback_5555 = EPwm1Regs.CMPA.half.CMPA;
    if (g_cmpa_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_CMPA)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_CMPA_5555);
    }

    EPwm1Regs.CMPA.half.CMPA = EPWM_REG_RW_WRITE_AAAA_16;
    g_cmpa_readback_aaaa = EPwm1Regs.CMPA.half.CMPA;
    if (g_cmpa_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_CMPA)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_CMPA_AAAA);
    }
}

static void check_aqctla_rw_masked(void)
{
    EPwm1Regs.AQCTLA.all = EPWM_REG_RW_WRITE_5555_16;
    g_aqctla_readback_5555 = EPwm1Regs.AQCTLA.all;
    if (g_aqctla_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_AQCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_AQCTLA_5555);
    }

    EPwm1Regs.AQCTLA.all = EPWM_REG_RW_WRITE_AAAA_16;
    g_aqctla_readback_aaaa = EPwm1Regs.AQCTLA.all;
    if (g_aqctla_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_AQCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_AQCTLA_AAAA);
    }
}

static void check_aqctlb_rw_masked(void)
{
    EPwm1Regs.AQCTLB.all = EPWM_REG_RW_WRITE_5555_16;
    g_aqctlb_readback_5555 = EPwm1Regs.AQCTLB.all;
    if (g_aqctlb_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_AQCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_AQCTLB_5555);
    }

    EPwm1Regs.AQCTLB.all = EPWM_REG_RW_WRITE_AAAA_16;
    g_aqctlb_readback_aaaa = EPwm1Regs.AQCTLB.all;
    if (g_aqctlb_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_AQCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_AQCTLB_AAAA);
    }
}

static void check_dbctl_rw_masked(void)
{
    EPwm1Regs.DBCTL.all = EPWM_REG_RW_WRITE_5555_16;
    g_dbctl_readback_5555 = EPwm1Regs.DBCTL.all;
    if (g_dbctl_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_DBCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBCTL_5555);
    }

    EPwm1Regs.DBCTL.all = EPWM_REG_RW_WRITE_AAAA_16;
    g_dbctl_readback_aaaa = EPwm1Regs.DBCTL.all;
    if (g_dbctl_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_DBCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBCTL_AAAA);
    }
}

static void check_dbred_rw_masked(void)
{
    EPwm1Regs.DBRED = EPWM_REG_RW_WRITE_5555_16;
    g_dbred_readback_5555 = EPwm1Regs.DBRED;
    if (g_dbred_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_DBRED)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBRED_5555);
    }

    EPwm1Regs.DBRED = EPWM_REG_RW_WRITE_AAAA_16;
    g_dbred_readback_aaaa = EPwm1Regs.DBRED;
    if (g_dbred_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_DBRED)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBRED_AAAA);
    }
}

static void check_dbfed_rw_masked(void)
{
    EPwm1Regs.DBFED = EPWM_REG_RW_WRITE_5555_16;
    g_dbfed_readback_5555 = EPwm1Regs.DBFED;
    if (g_dbfed_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_DBFED)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBFED_5555);
    }

    EPwm1Regs.DBFED = EPWM_REG_RW_WRITE_AAAA_16;
    g_dbfed_readback_aaaa = EPwm1Regs.DBFED;
    if (g_dbfed_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_DBFED)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_DBFED_AAAA);
    }
}

static void check_etsel_rw_masked(void)
{
    EPwm1Regs.ETSEL.all = EPWM_REG_RW_WRITE_5555_16;
    g_etsel_readback_5555 = EPwm1Regs.ETSEL.all;
    if (g_etsel_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_ETSEL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_ETSEL_5555);
    }

    EPwm1Regs.ETSEL.all = EPWM_REG_RW_WRITE_AAAA_16;
    g_etsel_readback_aaaa = EPwm1Regs.ETSEL.all;
    if (g_etsel_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_ETSEL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_ETSEL_AAAA);
    }
}

static void check_tbphshr_rw_masked(void)
{
    EPwm1Regs.TBPHS.half.TBPHSHR = EPWM_REG_RW_WRITE_5555_16;
    g_tbphshr_readback_5555 = EPwm1Regs.TBPHS.half.TBPHSHR;
    if (g_tbphshr_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_TBPHSHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPHSHR_5555);
    }

    EPwm1Regs.TBPHS.half.TBPHSHR = EPWM_REG_RW_WRITE_AAAA_16;
    g_tbphshr_readback_aaaa = EPwm1Regs.TBPHS.half.TBPHSHR;
    if (g_tbphshr_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_TBPHSHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPHSHR_AAAA);
    }
}

static void check_tbprdhr_rw_masked(void)
{
    EPwm1Regs.TBPRDHR = EPWM_REG_RW_WRITE_5555_16;
    g_tbprdhr_readback_5555 = EPwm1Regs.TBPRDHR;
    if (g_tbprdhr_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_TBPRDHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPRDHR_5555);
    }

    EPwm1Regs.TBPRDHR = EPWM_REG_RW_WRITE_AAAA_16;
    g_tbprdhr_readback_aaaa = EPwm1Regs.TBPRDHR;
    if (g_tbprdhr_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_TBPRDHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPRDHR_AAAA);
    }
}

static void check_cmpahr_rw_masked(void)
{
    EPwm1Regs.CMPA.half.CMPAHR = EPWM_REG_RW_WRITE_5555_16;
    g_cmpahr_readback_5555 = EPwm1Regs.CMPA.half.CMPAHR;
    if (g_cmpahr_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_CMPAHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_CMPAHR_5555);
    }

    EPwm1Regs.CMPA.half.CMPAHR = EPWM_REG_RW_WRITE_AAAA_16;
    g_cmpahr_readback_aaaa = EPwm1Regs.CMPA.half.CMPAHR;
    if (g_cmpahr_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_CMPAHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_CMPAHR_AAAA);
    }
}

static void check_hrcnfg_rw_masked(void)
{
    EALLOW;
    EPwm1Regs.HRCNFG.all = EPWM_REG_RW_WRITE_5555_16;
    EDIS;
    g_hrcnfg_readback_5555 = EPwm1Regs.HRCNFG.all;
    if (g_hrcnfg_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_HRCNFG)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRCNFG_5555);
    }

    EALLOW;
    EPwm1Regs.HRCNFG.all = EPWM_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_hrcnfg_readback_aaaa = EPwm1Regs.HRCNFG.all;
    if (g_hrcnfg_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_HRCNFG)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRCNFG_AAAA);
    }
}

static void check_hrpwr_rw_masked(void)
{
    EALLOW;
    EPwm1Regs.HRPWR.all = EPWM_REG_RW_WRITE_5555_16;
    EDIS;
    g_hrpwr_readback_5555 = EPwm1Regs.HRPWR.all;
    if (g_hrpwr_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_HRPWR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRPWR_5555);
    }

    EALLOW;
    EPwm1Regs.HRPWR.all = EPWM_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_hrpwr_readback_aaaa = EPwm1Regs.HRPWR.all;
    if (g_hrpwr_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_HRPWR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRPWR_AAAA);
    }
}

static void check_hrpctl_rw_masked(void)
{
    EALLOW;
    EPwm1Regs.HRPCTL.all = EPWM_REG_RW_WRITE_5555_16;
    EDIS;
    g_hrpctl_readback_5555 = EPwm1Regs.HRPCTL.all;
    if (g_hrpctl_readback_5555 !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_HRPCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRPCTL_5555);
    }

    EALLOW;
    EPwm1Regs.HRPCTL.all = EPWM_REG_RW_WRITE_AAAA_16;
    EDIS;
    g_hrpctl_readback_aaaa = EPwm1Regs.HRPCTL.all;
    if (g_hrpctl_readback_aaaa !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_HRPCTL)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRPCTL_AAAA);
    }
}

static void check_hr_mirror_write_aliases(void)
{
    EPwm1Regs.TBPRDM.half.TBPRDHR = EPWM_REG_RW_WRITE_5555_16;
    g_tbprdhrm_alias_readback = EPwm1Regs.TBPRDHR;
    if (g_tbprdhrm_alias_readback !=
        (EPWM_REG_RW_WRITE_5555_16 & EPWM_REG_RW_MASK_TBPRDHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_TBPRDHRM);
    }

    EPwm1Regs.CMPAM.half.CMPAHR = EPWM_REG_RW_WRITE_AAAA_16;
    g_cmpahrm_alias_readback = EPwm1Regs.CMPA.half.CMPAHR;
    if (g_cmpahrm_alias_readback !=
        (EPWM_REG_RW_WRITE_AAAA_16 & EPWM_REG_RW_MASK_CMPAHR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_CMPAHRM);
    }
}

static void check_hrpwr_32bit_packed_lane(void)
{
    volatile Uint32 *hrcnfg_hrpwr_pair;
    Uint32 packed_value;

    hrcnfg_hrpwr_pair = (volatile Uint32 *)&EPwm1Regs.HRCNFG.all;
    packed_value = ((Uint32)EPWM_REG_RW_PACKED_HRPWR_HIGH_16 << 16) |
                   (Uint32)EPWM_REG_RW_PACKED_HRCNFG_LOW_16;

    EALLOW;
    *hrcnfg_hrpwr_pair = packed_value;
    EDIS;

    g_hrcnfg_pack32_readback = EPwm1Regs.HRCNFG.all;
    if (g_hrcnfg_pack32_readback !=
        (EPWM_REG_RW_PACKED_HRCNFG_LOW_16 & EPWM_REG_RW_MASK_HRCNFG)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRCNFG_PACK32);
    }

    g_hrpwr_pack32_readback = EPwm1Regs.HRPWR.all;
    if (g_hrpwr_pack32_readback !=
        (EPWM_REG_RW_PACKED_HRPWR_HIGH_16 & EPWM_REG_RW_MASK_HRPWR)) {
        test_runtime_fail(EPWM_REG_RW_FAIL_RW_HRPWR_PACK32);
    }
}

void main(void)
{
    board_demo_init();
    epwm_init_case();
    capture_reset_snapshot();
    check_reset_values();
    prepare_rw_phase();
    check_tbprd_rw_masked();
    check_cmpa_rw_masked();
    check_aqctla_rw_masked();
    check_aqctlb_rw_masked();
    check_dbctl_rw_masked();
    check_dbred_rw_masked();
    check_dbfed_rw_masked();
    check_etsel_rw_masked();
    check_tbphshr_rw_masked();
    check_tbprdhr_rw_masked();
    check_cmpahr_rw_masked();
    check_hrcnfg_rw_masked();
    check_hrpwr_rw_masked();
    check_hrpctl_rw_masked();
    check_hrpwr_32bit_packed_lane();
    check_hr_mirror_write_aliases();
    test_runtime_pass();
}
