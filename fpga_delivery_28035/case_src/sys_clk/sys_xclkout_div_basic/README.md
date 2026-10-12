# sys_xclkout_div_basic

A system-control testcase that programs all four software-visible `XCLKOUTDIV`
settings and holds a runtime window after each setting for waveform or UVM
observation.

Purpose:

- provide direct software stimulus for `XCLKOUTDIV[1:0]`
- confirm register readback for each divider setting
- keep the CPU alive so `XCLKOUT` pad activity can be measured externally
- pair naturally with a UVM-side `xclkout` frequency/checker flow
