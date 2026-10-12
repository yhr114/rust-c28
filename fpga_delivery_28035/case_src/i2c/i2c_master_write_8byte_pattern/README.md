# i2c_master_write_8byte_pattern

This case verifies an 8-byte DUT I2C master write with an incrementing nibble pattern.

Expected transaction:

- address: 0x36
- direction: write
- length: 8 bytes
- data: 00 11 22 33 44 55 66 77
