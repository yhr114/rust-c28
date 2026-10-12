# i2c_master_write_then_read_4byte_basic

This smoke test programs DUT I2C as master, writes four bytes to VIP slave
address 0x36, then reads four deterministic bytes back from the VIP slave.

The VIP slave sequence and UVM monitor both use the fixed read pattern
`DE AD BE EF`, so the scoreboard can compare write data and read data without
an expected file or C-side mailbox.
