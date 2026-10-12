# sys_osc1_osc2_roundtrip_basic

A system-control testcase that forces PLL bypass (`InitPll(0, 0)`) and then
runs an `INTOSC1 -> INTOSC2 -> INTOSC1` round-trip.

Purpose:

- validate repeated internal-oscillator source switching in both directions
- provide a compact round-trip scenario for transition-settle and long-gap monitors
- keep the clock tree in bypass mode so the source path remains the primary variable
