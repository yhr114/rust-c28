sys_watchdog_timeout_reset_CASE_CATEGORY := system
sys_watchdog_timeout_reset_CASE_SRCS := src/main.c
sys_watchdog_timeout_reset_CASE_INCLUDES := include
sys_watchdog_timeout_reset_CASE_LINK_CMD := $(SDK_ROOT)/$(SRC_ROOT)/sys_watchdog_timeout_reset/linker_case.cmd
sys_watchdog_timeout_reset_EXPECTED_SYMBOLS := _main _pass _fail _exit
sys_watchdog_timeout_reset_SIM_APP_NAME := sys_watchdog_timeout_reset
