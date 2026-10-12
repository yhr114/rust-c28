# sys_intosc2_pll_basic

A system-control testcase that first switches `OSCCLK` to `INTOSC2`, then
programs a compact set of PLL `DIV/DIVSEL` profiles while keeping the source
selection fixed on `INTOSC2`.

Purpose:

- confirm the software-visible clock-source controls remain on `INTOSC2`
- confirm each programmed PLL profile reaches the expected `PLLCR.DIV` and
  `PLLSTS.DIVSEL` state
- confirm `PLLLOCKS` stays high and `MCLKSTS` stays low after each non-bypass
  profile
- leave a short observation window after each step so UVM can correlate
  `INTOSC2`-sourced PLL behavior with one explicit profile ID
