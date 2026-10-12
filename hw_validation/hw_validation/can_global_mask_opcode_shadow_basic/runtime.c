#include "board_can_case.h"
#include "test_runtime.h"
/* Replacement for absent SDK helpers, not the original SDK implementation.
   All eCAN control-register accesses use 32-bit .all accesses. */
volatile unsigned short test_status = 0, trace_count = 0, init_count = 0;
volatile unsigned short trace_enabled = 1;
volatile unsigned long test_fail_code = 0;
struct SNAP { unsigned long stage, me, md, mim, mil, ta, rmp, trs, mc, es, gam, lam0, id, ctrl, lo, hi; };
volatile struct SNAP trace[10];
/* Volatile RAM shadow prevents compiler folding a masked .all read into
   a 16-bit TBIT instruction on the peripheral register. */
static unsigned long read_can_es(void)
{
    volatile unsigned long shadow;
    shadow=ECanaRegs.CANES.all;
    return shadow;
}
void snapshot(unsigned long stage)
{
    volatile struct SNAP *s;
    if(!trace_enabled || trace_count >= 10) return;
    s = &trace[trace_count++];
    s->stage=stage;
    s->me=ECanaRegs.CANME.all; s->md=ECanaRegs.CANMD.all;
    s->mim=ECanaRegs.CANMIM.all; s->mil=ECanaRegs.CANMIL.all;
    s->ta=ECanaRegs.CANTA.all; s->rmp=ECanaRegs.CANRMP.all;
    s->trs=ECanaRegs.CANTRS.all; s->mc=ECanaRegs.CANMC.all;
    s->es=ECanaRegs.CANES.all; s->gam=ECanaRegs.CANGAM.all;
    s->lam0=ECanaLAMRegs.LAM0.all;
    s->id=ECanaMboxes.MBOX0.MSGID.all; s->ctrl=ECanaMboxes.MBOX0.MSGCTRL.all;
    s->lo=ECanaMboxes.MBOX0.MDL.all; s->hi=ECanaMboxes.MBOX0.MDH.all;
}
void test_done(void) { asm(" ESTOP0"); for(;;) {} }
void test_runtime_pass(void) { test_status=1; snapshot(9); test_done(); }
void test_runtime_fail(unsigned long c) { test_fail_code=c; test_status=2; snapshot(99); test_done(); }
void board_demo_init(void)
{
    DINT; IER=0; IFR=0;
    EALLOW;
    SysCtrlRegs.WDCR=0x0068;
    SysCtrlRegs.PCLKCR0.bit.ECANAENCLK=1;
    EDIS;
    snapshot(0);
}
void can_case_basic_init(unsigned int selftest)
{
    unsigned long t, mc;
    unsigned int i;
    volatile struct MBOX *mb = &ECanaMboxes.MBOX0;
    snapshot(init_count ? 3 : 1);
    EALLOW;
    ECanaRegs.CANME.all=0;
    ECanaRegs.CANMD.all=0;
    ECanaRegs.CANMIM.all=0;
    ECanaRegs.CANMIL.all=0;
    ECanaRegs.CANTA.all=0xFFFFFFFFUL;
    ECanaRegs.CANRMP.all=0xFFFFFFFFUL;
    ECanaRegs.CANGIF0.all=0xFFFFFFFFUL;
    ECanaRegs.CANGIF1.all=0xFFFFFFFFUL;
    /* Keep GPIO mux unchanged: self-test does not need an external CAN bus. */
    ECanaRegs.CANTIOC.all=0x8UL;
    ECanaRegs.CANRIOC.all=0x8UL;
    mc=0x2000UL | (selftest ? 0x40UL : 0UL);
    ECanaRegs.CANMC.all=mc | 0x1000UL;
    for(t=0;t<200000UL;t++) if(read_can_es() & 0x10UL) break;
    if(t==200000UL) { EDIS; test_runtime_fail(0xE001UL); }
    ECanaRegs.CANBTC.all=0x00020016UL;
    for(i=0;i<32;i++) { mb[i].MSGCTRL.all=0; mb[i].MSGID.all=0; mb[i].MDL.all=0; mb[i].MDH.all=0; }
    ECanaRegs.CANMC.all=mc;
    for(t=0;t<200000UL;t++) if(!(read_can_es() & 0x10UL)) break;
    EDIS;
    if(t==200000UL) test_runtime_fail(0xE002UL);
    snapshot(init_count ? 4 : 2);
    init_count++;
}
void can_case_setup_tx_mbox(unsigned int box, unsigned long id, unsigned long dlc, unsigned long lo, unsigned long hi)
{
    volatile struct MBOX *mb=&ECanaMboxes.MBOX0;
    unsigned long mask=1UL<<box;
    ECanaRegs.CANME.all &= ~mask;
    ECanaRegs.CANMD.all &= ~mask;
    mb[box].MSGID.all=(id & 0x7FFUL)<<18;
    mb[box].MSGCTRL.all=dlc & 15UL;
    mb[box].MDL.all=lo; mb[box].MDH.all=hi;
    ECanaRegs.CANME.all |= mask;
    snapshot(5);
}
void can_case_send(unsigned int box) { ECanaRegs.CANTRS.all=1UL<<box; snapshot(6); }
unsigned int can_case_wait_for_mask(volatile unsigned long *reg, unsigned long mask, unsigned long loops)
{
    while(loops--) if((*reg & mask)==mask) { snapshot(7); return 0; }
    snapshot(70); return 1;
}
void can_case_clear_tx_ack(unsigned int box) { ECanaRegs.CANTA.all=1UL<<box; snapshot(8); }
void can_case_enter_config(void)
{
    unsigned long t;
    ECanaRegs.CANMC.all |= 0x2000UL;              /* CCR=1 */
    for(t=0;t<200000UL;t++) if(read_can_es() & 0x10UL) break;     /* wait CCE */
    if(t==200000UL) test_runtime_fail(0xE003UL);
}
void can_case_leave_config(void)
{
    unsigned long t;
    ECanaRegs.CANMC.all &= ~0x2000UL;             /* CCR=0 */
    for(t=0;t<200000UL;t++) if(!(read_can_es() & 0x10UL)) break;  /* wait CCE clear */
    if(t==200000UL) test_runtime_fail(0xE004UL);
}
volatile struct MBOX *can_case_mbox_ptr(unsigned int box)
{
    return &ECanaMboxes.MBOX0 + box;
}
void can_case_setup_rx_mbox(unsigned int box, unsigned long id)
{
    volatile struct MBOX *mb=&ECanaMboxes.MBOX0;
    unsigned long mask=1UL<<box;
    ECanaRegs.CANME.all &= ~mask;
    ECanaRegs.CANMD.all &= ~mask;                 /* RX direction */
    mb[box].MSGID.all=(id & 0x7FFUL)<<18;
    mb[box].MSGCTRL.all=0;
    mb[box].MDL.all=0; mb[box].MDH.all=0;
    ECanaRegs.CANRMP.all=mask;                    /* clear pending */
    /* Caller sets LAM and re-enables CANME. */
}
volatile union CANLAM_REG *can_case_lam_ptr(unsigned int box)
{
    return &ECanaLAMRegs.LAM0 + box;
}
unsigned long can_case_read_rx_data_lo(unsigned int box)
{
    return (&ECanaMboxes.MBOX0 + box)->MDL.all;
}
unsigned long can_case_read_rx_data_hi(unsigned int box)
{
    return (&ECanaMboxes.MBOX0 + box)->MDH.all;
}
void can_case_clear_rx_pending(unsigned int box) { ECanaRegs.CANRMP.all=1UL<<box; }
