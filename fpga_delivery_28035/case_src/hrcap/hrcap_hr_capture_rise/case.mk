hrcap_hr_capture_rise_CASE_CATEGORY := periph
hrcap_hr_capture_rise_CASE_SRCS := src/main.c src/DSP2803x_HRCap.c
hrcap_hr_capture_rise_CASE_INCLUDES := include
hrcap_hr_capture_rise_CASE_CFLAGS := --include_path=/scratch/tools/ti/lib/C2000Ware_5_02_00_00/device_support/f2803x/common/include --include_path=/scratch/tools/ti/lib/C2000Ware_5_02_00_00/device_support/f2803x/headers/include --include_path=/scratch/tools/ti/lib/C2000Ware_5_02_00_00/libraries/calibration/hrcap/common/type0/include
hrcap_hr_capture_rise_CASE_LFLAGS := --undef_sym=_HRCAP_Cal /scratch/tools/ti/lib/C2000Ware_5_02_00_00/libraries/calibration/hrcap/f2803x/lib/HCCal_Type0_V1.lib
hrcap_hr_capture_rise_EXPECTED_SYMBOLS := _main _pass _fail _exit
hrcap_hr_capture_rise_SIM_APP_NAME := hrcap_hr_capture_rise
