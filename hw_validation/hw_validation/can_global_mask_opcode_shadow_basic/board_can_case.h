#ifndef BOARD_CAN_CASE_H
#define BOARD_CAN_CASE_H
#include "DSP28x_Project.h"
#define CAN_CASE_TX_MBOX0 0U
#define CAN_CASE_RX_MBOX1 1U
#define CAN_CASE_STD_ID(id) (((id) & 0x7FFUL) << 18)
void board_demo_init(void);
void can_case_basic_init(unsigned int selftest);
void can_case_setup_tx_mbox(unsigned int box, unsigned long id, unsigned long dlc, unsigned long lo, unsigned long hi);
void can_case_send(unsigned int box);
unsigned int can_case_wait_for_mask(volatile unsigned long *reg, unsigned long mask, unsigned long loops);
void can_case_clear_tx_ack(unsigned int box);
void can_case_enter_config(void);
void can_case_leave_config(void);
volatile struct MBOX *can_case_mbox_ptr(unsigned int box);
void can_case_setup_rx_mbox(unsigned int box, unsigned long id);
volatile union CANLAM_REG *can_case_lam_ptr(unsigned int box);
unsigned long can_case_read_rx_data_lo(unsigned int box);
unsigned long can_case_read_rx_data_hi(unsigned int box);
void can_case_clear_rx_pending(unsigned int box);
#endif
