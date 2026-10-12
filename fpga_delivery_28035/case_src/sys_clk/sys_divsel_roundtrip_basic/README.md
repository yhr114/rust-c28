# sys_divsel_roundtrip_basic

A system-control testcase that keeps `PLLCR.DIV` fixed and performs a
round-trip `DIVSEL` sweep to exercise both upward and downward transitions.

Purpose:

- hold `PLLCR.DIV` at a constant value
- sweep `DIVSEL` through `0 -> 1 -> 2 -> 3 -> 2 -> 1 -> 0`
- provide a stable observation window after each transition
