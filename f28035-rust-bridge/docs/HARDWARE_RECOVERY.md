# F28035 Flash / CSM Status

## Current board status (read-only verification, 2026-09-22)

The connected TMS320F28035 is **not password locked**.

The following observations were made through XDS100v1 and CCS DSS without an
erase, program, unlock, KEY-register write, target reset, or program load:

- CSM password locations `0x3F7FF8..0x3F7FFF` read as eight `0xFFFF` words.
- Reading those eight erased password words completed the normal dummy-read
  sequence; `CSMSCR @ 0x0AEF` then read `0x0070`, so `SECURE` (bit 0) was clear.
- `FSTATUS @ 0x0A83` read `0x0003`: the Flash bank/pump was active in read
  mode and the 3.3-V error latch (bit 8) was clear.
- Valid user-Flash addresses contained existing data (`0x3E8000=0x2111`,
  `0x3F0000=0x1901`, `0x3F6000=0x761B`).

`0x3F8000` is **not user Flash** on F28035. It is the program-space mirror of
L0 SARAM. Values read there describe RAM contents and are not evidence about
Flash health. F28034/F28035 user Flash is `0x3E8000..0x3F7FFF`.

## Why the earlier lock diagnosis was wrong

An erased-password device can appear secure immediately after reset until the
eight password locations have been dummy-read. Treating that transient state as
an unknown-password lock produced the earlier incorrect diagnosis.

The previous `tools/try-flash-load.js` connected and called `loadProgram`
immediately. The guarded GPIO34 programming flow now performs the erased-
password dummy reads, checks that all words are `0xFFFF`, and confirms
`CSMSCR.SECURE == 0` before allowing the CCS Flash loader to run.

## Current Flash workflow

The older `build-mir-gpio34-output.ps1` currently links with
`tools/F28035_ram.cmd`. Its Flash-named wrapper is not evidence of a
persistent image and should not be used to program the board. Use the
one-file build and explicit guarded programming workflow in
`ONE_FILE_MAIN.md` instead.

That workflow builds a separate sector-A image and rejects every loadable
segment outside the sector-A code area or the two-word boot entry. Before
programming it backs up all user Flash and checks erased, unprotected CSM
passwords. Its Flash-only startup copies `ramfuncs` to RAM before calling
`InitFlash()`. After programming, it verifies a Boot-ROM reset without
forcing PC; the physical power-loss test remains a separate manual step.

GPIO34/GPIO37 must select boot-to-Flash at reset. Never interrupt power
during a Flash erase/program operation. Do not use images that contain a
loadable `CsmPwlFile` section.
