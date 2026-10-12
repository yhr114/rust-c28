# sys_pll_bypass_basic

A system-control testcase that drives the PLL path into the `DIV=0 / DIVSEL=0`
software-visible bypass state and keeps the CPU alive long enough for UVM or
waveform checks to observe the clock-tree reaction.

Purpose:

- program a software-visible PLL bypass style configuration
- confirm `MCLKSTS` stays clear
- confirm `PLLCR.DIV == 0`
- confirm `PLLSTS.DIVSEL == 0`
- provide a stable runtime observation window for clock-tree monitors
