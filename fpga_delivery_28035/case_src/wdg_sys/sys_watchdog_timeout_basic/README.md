# sys_watchdog_timeout_basic

A minimal watchdog baseline testcase focused on counter activity and feed behavior.

Purpose:

- confirm the watchdog can be re-enabled after init
- confirm the watchdog counter progresses in simulation
- confirm feeding the watchdog restarts counter activity
- provide a simple pass/fail baseline for system-level regression

Flow:

- initialize the board and device environment
- feed the watchdog and enable it with a legal WDCR value
- observe that `WDCNTR` changes from its snapshot
- feed the watchdog again and confirm counter progress restarts
- disable the watchdog before leaving the testcase

Fail Codes:

- `0x4301`: watchdog counter did not make forward progress after enable
- `0x4302`: watchdog counter did not restart after a second feed

Notes:

- this testcase intentionally does not wait for a real watchdog timeout/reset
- it is meant to stay lightweight and deterministic
- a dedicated timeout/reset testcase should cover `WDFLAG`, `XRS`, and boot recovery
