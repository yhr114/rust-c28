# adc_single_soc_basic

A first runnable ADC smoke testcase for the current SDK + UVM platform.

Purpose in v1:

- enable and power up the ADC wrapper
- configure one software-triggered SOC
- configure one ADC interrupt source
- read back key ADC control fields
- prove the basic ADC register/config path is alive in simulation

Important limitation for v1:

- this case does **not** require real ADC conversion completion
- it does **not** check `EOC`, `ADCINT1`, or `ADCRESULT0`
- current platform analog stubs are not yet strong enough to make that path stable

So the current smoke focus is:

`ADC clock -> ADC control regs -> SOC0 config -> readback checks`

Typical usage:

```bash
cd /scratch/home/wxu/work/s03_sdk
make adc_single_soc_basic VERSION=28035 BOOT=sram
```
