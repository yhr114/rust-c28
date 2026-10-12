# epwm_clkdiv_hspclkdiv_matrix

Purpose: exercise EPWM1 time-base clock divider programming and emit a visible
PWM waveform segment for each divider combination.

The C case walks these `HSPCLKDIV/CLKDIV` combinations:

| HSPCLKDIV field | HSP divider | CLKDIV field | CLK divider | Total scaler |
| --- | --- | --- | --- | --- |
| 0 | /1 | 0 | /1 | /1 |
| 1 | /2 | 0 | /1 | /2 |
| 2 | /4 | 0 | /1 | /4 |
| 3 | /6 | 0 | /1 | /6 |
| 0 | /1 | 1 | /2 | /2 |
| 1 | /2 | 1 | /2 | /4 |
| 2 | /4 | 1 | /2 | /8 |
| 3 | /6 | 1 | /2 | /12 |
| 4 | /8 | 2 | /4 | /32 |

Each configuration runs for `EPWM_CLKDIV_CONFIG_RUN_US`, then the case checks
divider/readback state before moving to the next configuration. The final active
configuration is `/32`, and it remains running for an additional
`EPWM_CLKDIV_FINAL_RUN_DELAY_US` so the UVM scoreboard can strongly check the
stable final period/high-time using the clock scaler.

The UVM policy reuses the normal up-count waveform checker. Intermediate
segments are intended for waveform visibility and C readback coverage; the
current UVM checker intentionally treats the final stable configuration as the
strong pass/fail point.
