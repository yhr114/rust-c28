# i2c_master_write_back_to_back

This case verifies two consecutive DUT I2C master write transactions to the same VIP slave.

Expected transactions:

1. address 0x36, write, 4 bytes: a5 5a 3c c3
2. address 0x36, write, 6 bytes: 10 20 30 40 50 60
