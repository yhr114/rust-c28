watchdog_reset_mode_test_CASE_CATEGORY := watchdog
watchdog_reset_mode_test_CASE_SRCS := src/main.c
watchdog_reset_mode_test_CASE_INCLUDES := include
watchdog_reset_mode_test_CASE_LINK_CMD := $(SDK_ROOT)/$(SRC_ROOT)/watchdog_reset_mode_test/linker_case.cmd
watchdog_reset_mode_test_EXPECTED_SYMBOLS := _main _pass _fail _exit
watchdog_reset_mode_test_SIM_APP_NAME := watchdog_reset_mode_test
