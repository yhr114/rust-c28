# SPI FIFO level boundary — F28035 hardware validation

Prepared on 2026-09-04 using CCS 20.1.1, C2000 compiler 22.6.1.LTS,
C2000Ware 26.01.00.00, and the user's XDS100v1/F28035 target configuration.

## Current status

Compilation and RAM linking succeeded. After the user power-cycled the hardware,
connection, RAM download and both runs succeeded. Both returned FAIL 0x533002.
The final run.log and results.json contain the verified results. Each run was
confirmed halted at main before setting and reading back validation_mode, and
then stopped at ESTOP0 (PC 0x804A) after capturing its result.

| Captured field | Mode 0: minimal init | Mode 1: loopback master |
|---|---|---|
| test_status | 0x2 (FAIL) | 0x2 (FAIL) |
| test_fail_code | 0x533002 | 0x533002 |
| SPICCR | 0x0000 | 0x009F |
| SPICTL | 0x0000 | 0x0006 |
| SPIFFTX (0x704A) | 0xE080 | 0xE080 |
| SPIFFRX (0x704B) | 0x201F | 0x2080 |
| SPIDAT (0x7049) | 0x0011 | 0x0011 |

The immediate TXFFST assertion failed in both runs. SPIDAT contained the written
word although TXFFST was zero. This supports downstream transfer as the reason
the nonzero-FIFO assumption fails; it does not by itself verify a complete serial
transfer or FIFO full-boundary behavior. In mode 0 SPICCR/SPICTL were at reset
(SPICCR=0, SPICTL=0), so no completed pin transmission should be inferred.

Initial connection errors -1155/-1015/-1156 cleared after the power cycle.
run_initial.log records an intermediate script issue: CCS auto-ran to main on
load, and an extra run executed the case before selecting the comparison mode.
Those mode labels are invalid. The corrected script checks PC and mode readback;
only run.log/results.json are the final comparison evidence.

## Reproduction scope

The original case main.c is copied without edits by build.ps1.
SHA256: C5777FCA4F830CD98C977AE564E6072D8956E9D77542F126D4004453DECBE7D5.

The original board_spi_case.h and device_sdk_init implementation are absent.
The supplied adapter uses TI word addresses SPITXBUF=0x7048 and SPIFFTX=0x704A,
volatile 16-bit MMIO, disables interrupts/watchdog, and enables the SPI-A clock.
It does not reproduce unknown original SDK initialization or access timing.

run.js prepares two separately reset runs of the same main.c:

1. Mode 0: minimal initialization; SPI configuration otherwise remains at reset.
2. Mode 1: explicit 16-bit internal-loopback master initialization.

Results are captured by the adapter before ESTOP0. Mode 1 is a controlled
comparison, not an assertion about the original SDK configuration.

## Files and execution

Run build.ps1 to rebuild. It stages files under the ASCII path
C:/Users/32917/AppData/Local/Temp/spi_fifo_28035_20260904 for TI tool compatibility.
case.out and case.map are copied here. TI's 28035_RAM_lnk.cmd places loadable
sections in RAM; no Flash programming is requested.

Copy run.js to the staging directory, then execute it with:

```powershell
& C:\ti\ccs2011\ccs\scripting\run.bat C:\Users\32917\AppData\Local\Temp\spi_fifo_28035_20260904\run.js
```

The stage contains target.ccxml with a 100 kHz JTAG clock for connection diagnosis.
Hardware must be accessible before execution can proceed.
