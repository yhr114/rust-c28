i2c_master_write_8byte_pattern_CASE_CATEGORY := smoke
i2c_master_write_8byte_pattern_CASE_SRCS := src/main.c
i2c_master_write_8byte_pattern_CASE_INCLUDES := include
i2c_master_write_8byte_pattern_CASE_LINK_CMD := $(SDK_ROOT)/$(SRC_ROOT)/i2c_common/28035_RAM_lnk_i2c_case.cmd
i2c_master_write_8byte_pattern_EXPECTED_SYMBOLS := _main _pass _fail _exit
i2c_master_write_8byte_pattern_SIM_APP_NAME := i2c_master_write_8byte_pattern
