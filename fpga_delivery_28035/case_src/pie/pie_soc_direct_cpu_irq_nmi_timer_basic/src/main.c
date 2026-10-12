#include "board_gpio.h"
#include "case_config.h"
#include "test_runtime.h"

#if !defined(DEVICE_28035)
#error "pie_soc_direct_cpu_irq_nmi_timer_basic only supports VERSION=28035"
#endif

#include "device_28035.h"

#define S03_REG16(addr)      (*((volatile Uint16 *)(addr)))
#define S03_CLKCTL_ADDR      0x00007012UL
#define S03_NMICFG_ADDR      0x00007060UL
#define S03_NMIFLG_ADDR      0x00007061UL
#define S03_NMIFLGCLR_ADDR   0x00007062UL
#define S03_NMIFLGFRC_ADDR   0x00007063UL
#define S03_NMIWDPRD_ADDR    0x00007065UL

#define S03_NMICFG_CLOCKFAIL_IE_MASK  0x0002U
#define S03_NMIFLG_NMIINT_MASK        0x0001U
#define S03_NMIFLG_CLOCKFAIL_MASK     0x0002U
#define S03_NMIFLGCLR_ALL_MASK        0x0003U
#define S03_NMIFLGFRC_CLOCKFAIL_MASK  0x0002U

#define PIE_SOC_TCR_STOP_CLEAR        0x8010U
#define PIE_SOC_TCR_STOP_TIE_RELOAD   0xC030U
#define PIE_SOC_TCR_START_TIE         0xC000U

volatile Uint16 g_pie_soc_direct_stage;
volatile Uint16 g_pie_soc_direct_nmicfg_saved;
volatile Uint16 g_pie_soc_direct_nmiwdprd_saved;
volatile Uint16 g_pie_soc_direct_nmi_flags;
volatile Uint16 g_pie_soc_direct_timer_seen;
volatile Uint16 g_pie_soc_direct_nmi_isr_count;
volatile Uint32 g_pie_soc_direct_timer1_start;
volatile Uint32 g_pie_soc_direct_timer1_end;
volatile Uint32 g_pie_soc_direct_timer2_start;
volatile Uint32 g_pie_soc_direct_timer2_end;


interrupt void pie_soc_direct_nmi_isr(void)
{
    g_pie_soc_direct_nmi_isr_count++;
    EALLOW;
    S03_REG16(S03_NMIFLGCLR_ADDR) = S03_NMIFLGCLR_ALL_MASK;
    EDIS;
}

static void install_direct_irq_handlers(void)
{
    DINT;
    IER = 0x0000U;
    IFR = 0x0000U;
    EALLOW;
    PieVectTable.NMI = &pie_soc_direct_nmi_isr;
    EDIS;
}

static void write_reg16(unsigned long addr, Uint16 value)
{
    EALLOW;
    S03_REG16(addr) = value;
    EDIS;
    board_delay_us(PIE_SOC_DIRECT_SETTLE_US);
}

static Uint16 wait_nmi_isr_count(void)
{
    unsigned long poll;

    for (poll = 0UL; poll < PIE_SOC_DIRECT_POLL_LIMIT; poll++) {
        if (g_pie_soc_direct_nmi_isr_count != 0U) {
            return g_pie_soc_direct_nmi_isr_count;
        }
        board_delay_us(PIE_SOC_DIRECT_POLL_DELAY_US);
    }
    return g_pie_soc_direct_nmi_isr_count;
}

static void enable_timer_clocks(void)
{
    EALLOW;
    SysCtrlRegs.PCLKCR3.bit.CPUTIMER1ENCLK = 1U;
    SysCtrlRegs.PCLKCR3.bit.CPUTIMER2ENCLK = 1U;
    SysCtrlRegs.CLKCTL.bit.TMR2CLKSRCSEL = 0U;
    SysCtrlRegs.CLKCTL.bit.TMR2CLKPRESCALE = 0U;
    EDIS;
    board_delay_us(PIE_SOC_DIRECT_SETTLE_US);
}

static Uint16 run_timer_pulse(volatile struct CPUTIMER_REGS *regs,
                              volatile Uint32 *start_sample,
                              volatile Uint32 *end_sample)
{
    unsigned long poll;

    regs->TCR.all = PIE_SOC_TCR_STOP_CLEAR;
    regs->PRD.all = PIE_SOC_DIRECT_TIMER_PERIOD;
    regs->TPR.all = 0U;
    regs->TPRH.all = 0U;
    regs->TCR.all = PIE_SOC_TCR_STOP_TIE_RELOAD;
    board_delay_us(PIE_SOC_DIRECT_SETTLE_US);

    *start_sample = regs->TIM.all;
    regs->TCR.all = PIE_SOC_TCR_START_TIE;

    for (poll = 0UL; poll < PIE_SOC_DIRECT_TIMER_POLL_LIMIT; poll++) {
        if (regs->TCR.bit.TIF != 0U) {
            *end_sample = regs->TIM.all;
            regs->TCR.all = PIE_SOC_TCR_STOP_CLEAR;
            return 1U;
        }
    }

    *end_sample = regs->TIM.all;
    regs->TCR.all = PIE_SOC_TCR_STOP_CLEAR;
    return 0U;
}

static void trigger_crs_nmi_path(void)
{
    g_pie_soc_direct_stage = 2U;
    g_pie_soc_direct_nmicfg_saved = S03_REG16(S03_NMICFG_ADDR);
    g_pie_soc_direct_nmiwdprd_saved = S03_REG16(S03_NMIWDPRD_ADDR);

    write_reg16(S03_NMIFLGCLR_ADDR, S03_NMIFLGCLR_ALL_MASK);
    write_reg16(S03_NMIWDPRD_ADDR, 0xFFFFU);
    write_reg16(S03_NMICFG_ADDR,
                (Uint16)(g_pie_soc_direct_nmicfg_saved | S03_NMICFG_CLOCKFAIL_IE_MASK));
    g_pie_soc_direct_nmi_isr_count = 0U;
    write_reg16(S03_NMIFLGFRC_ADDR, S03_NMIFLGFRC_CLOCKFAIL_MASK);
    g_pie_soc_direct_nmi_flags = wait_nmi_isr_count();
    if (g_pie_soc_direct_nmi_flags == 0U) {
        test_runtime_fail(PIE_SOC_DIRECT_FAIL_NMI_FLAG);
    }

    write_reg16(S03_NMIFLGCLR_ADDR, S03_NMIFLGCLR_ALL_MASK);
    write_reg16(S03_NMICFG_ADDR, g_pie_soc_direct_nmicfg_saved);
    write_reg16(S03_NMIWDPRD_ADDR, g_pie_soc_direct_nmiwdprd_saved);
}

void main(void)
{
    board_demo_init();
    board_demo_toggle();
    DisableDog();
    install_direct_irq_handlers();
    InitPll(0U, 0U);
    board_delay_us(PIE_SOC_DIRECT_SETTLE_US);

    g_pie_soc_direct_stage = 1U;
    enable_timer_clocks();

    trigger_crs_nmi_path();

    g_pie_soc_direct_stage = 3U;
    if (run_timer_pulse(&CpuTimer1Regs,
                        &g_pie_soc_direct_timer1_start,
                        &g_pie_soc_direct_timer1_end) == 0U) {
        test_runtime_fail(PIE_SOC_DIRECT_FAIL_TIMER1_TIF);
    }
    g_pie_soc_direct_timer_seen |= 0x0001U;

    g_pie_soc_direct_stage = 4U;
    if (run_timer_pulse(&CpuTimer2Regs,
                        &g_pie_soc_direct_timer2_start,
                        &g_pie_soc_direct_timer2_end) == 0U) {
        test_runtime_fail(PIE_SOC_DIRECT_FAIL_TIMER2_TIF);
    }
    g_pie_soc_direct_timer_seen |= 0x0002U;

    board_demo_toggle();
    g_pie_soc_direct_stage = 5U;
    test_runtime_pass();
}
