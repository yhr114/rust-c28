# sys_watchdog_timeout_reset

A watchdog reset-path testcase that intentionally stops feeding the watchdog and expects the device to reboot through the watchdog reset path.

Purpose:

- confirm the watchdog can be armed in reset mode
- confirm software can distinguish cold boot versus watchdog-reset boot using `WDFLAG`
- confirm the first boot does not reach PASS before a watchdog reset occurs
- confirm the second boot observes `WDFLAG=1`, clears the flag, disables the watchdog, and then reports PASS

Flow:

- initialize the board and device environment
- if `WDFLAG` is already set, treat the run as the post-watchdog-reset boot:
  - disable the watchdog and clear `WDFLAG`
  - verify `WDFLAG` cleared
  - report PASS
- otherwise treat the run as the first boot:
  - service the watchdog once
  - force watchdog reset mode
  - stop feeding the watchdog
  - wait long enough for a watchdog timeout reset
  - if no reset occurs, report FAIL

Fail Codes:

- `0x4401`: unexpected `WDFLAG` state while deciding the boot stage
- `0x4402`: watchdog did not stay in reset mode after configuration
- `0x4403`: watchdog timeout reset did not occur within the wait window
- `0x4404`: `WDFLAG` did not clear after software requested clear+disable

Notes:

- this testcase is the reset-path companion to `sys_watchdog_timeout_basic`
- it is intended to validate timeout-reset recovery, not interrupt-mode `WAKEINT`
- TB should still observe `WDRST/XRS`, reset release, reboot, and final PASSADDR
