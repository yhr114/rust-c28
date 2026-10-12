# sys_pll_lock_basic

A minimal system-control testcase that checks the post-init PLL state.

Purpose:

- confirm `InitSysCtrl()` completed without missing-clock limp mode
- confirm the PLL reports locked
- confirm `PLLCR.DIV` and `PLLSTS.DIVSEL` match the SDK example defaults
- provide the first real system-control oriented pass/fail case
