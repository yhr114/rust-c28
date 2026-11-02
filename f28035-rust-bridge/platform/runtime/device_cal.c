/* Calls the F2803x boot-ROM Device_cal() at 0x3D7C80, which copies the factory
 * ADC calibration (ADCREFTRIM/ADCOFFTRIM) from TI OTP.
 *
 * A RAM/JTAG image that forces PC to code_start bypasses the boot ROM, so this
 * must be called explicitly -- with the ADC clock enabled -- before powering up
 * the converter.  Without it the ADC runs with its reset trim and conversions
 * are out of specification (the vendor DSP2803x_Adc.c::InitAdc comment says
 * exactly this).
 */
typedef void (*f28035_cal_fn)(void);

void f28035_device_cal(void)
{
    ((f28035_cal_fn)0x3D7C80)();
}
