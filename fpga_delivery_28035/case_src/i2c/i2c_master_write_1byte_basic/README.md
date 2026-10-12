# i2c_master_write_1byte_basic

This case verifies the smallest DUT I2C master write transaction to VIP slave address 0x36.

Expected transaction:

- address: 0x36
- direction: write
- length: 1 byte
- data: 5a
