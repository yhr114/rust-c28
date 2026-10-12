# i2c_master_addr_nack_stop_basic

VIP slave intentionally NACKs the 7-bit address phase. The SDK case expects NACK, waits for STOP/bus idle, and then passes.

Coverage intent:

- master FSM: RES_ADDR_ACK to FRAME_DONE/TX_STOP NACK path
- address: 0x36
- direction: write attempt
- expected result: address NACK observed by DUT master
