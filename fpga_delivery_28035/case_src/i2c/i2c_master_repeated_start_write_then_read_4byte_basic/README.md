# I2C repeated-start write then read 4 byte basic

Writes four bytes without STOP, waits for ARDY, then issues a repeated START read with STOP. This targets master TX_RESTART/repeated-start style FSM coverage while keeping the case local to the SDK example.
