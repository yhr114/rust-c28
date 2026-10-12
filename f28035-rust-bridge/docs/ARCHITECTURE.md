# Architecture

This document explains how f28035-rust-bridge works.

## Two-Track Design

This project has two top-level tracks.  They meet again at the TI CGT linker /
CCS/XDS100 hardware verification boundary, but they answer different questions:

1. **Application track (`app/` + `sdk/`)**: keep the existing TI/CCS board flow
   working while moving product logic behind Safe Rust APIs.
2. **Compiler track (`crates/` + `backend/`)**: prove that selected Safe Rust
   code can be lowered from rustc MIR/LLVM into C28x code without going through
   the app-path Rust-to-C translator.

### Track 1: Application Development

```
app/ Rust case
  -> sdk/f28035-safe-hal safe API
  -> sdk/c-abi narrow C bridge
  -> TI headers / startup / linker scripts / C2000 support code
  -> tools/build-case.ps1
  -> TI CGT .out
  -> CCS/XDS100 RAM or Flash load
  -> JTAG verification
```

This is the engineering path for board bring-up and product-style cases.  It is
allowed to keep CCS, TI CGT, TI headers, startup files, linker scripts and a
small audited C ABI underneath the HAL.  Its safety value comes from making the
application/control layer use Safe Rust handles instead of raw C calls or naked
register writes.

Current status:

- The build and JTAG verification flow is usable.
- Seven GPIO cases are formal Safe HAL bridge cases: `gpio_output_basic`,
  `gpio_output_readback_basic`, `gpio_toggle_basic`, and
  `gpio_direction_switch_basic`, plus `gpio2_3_low`, `gpio30_low`, and
  `gpio_mux_basic`.  They are tracked in the app case registry, their app
  sources use the Safe HAL, and `tools/verify-safe-hal-case-ram.ps1` verifies
  the target through rustc MIR -> `backend/c28x-mir` -> RAM/JTAG.
- `integration/safe_hal_control_loop` extends the bridge beyond GPIO: ADC0
  samples drive ePWM1 CMPA and GPIO31, while Timer0 periodic interrupts are
  verified by the RAM/JTAG control-loop harness.
- Three focused non-GPIO bridge cases are also verified through the same route:
  `adc/adc_sample_basic`, `epwm/epwm_cmp_basic`, and
  `timer/timer0_periodic_basic`.
- Most other app hardware cases still use direct `extern "C"`/`unsafe` or the
  restricted Rust-to-C translator path; they should not yet be described as
  fully Safe Rust end-to-end.
- The next application-track milestone is to add GPIO input/loopback and then
  extend the same Safe HAL bridge pattern to communication/capture peripherals.

### Track 2: Compiler Research

The compiler track has two backend variants:

```
┌─────────────────────────────────────────────────────────────────┐
│  PATH 2A (current, working subset) — Out-of-tree MIR analyzer   │
│                                                                 │
│  Rust source ──► rustc ──► MIR ──► [our analyzer] ──► C28x asm │
│                                        │                        │
│                                   classify_mmio_write_sequence │
│                                        │                        │
│                                   emit_mir_function             │
│                                        │                        │
│                                   TI CGT linker ──► .out ──► flash
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  PATH 2B (future) — Real LLVM backend                           │
│                                                                 │
│  Rust source ──► rustc ──► LLVM IR ──► [C28x backend] ──► asm  │
│                                        │                        │
│                                   ISelDAGToDAG                  │
│                                   RegAlloc                      │
│                                   FrameLowering                 │
│                                   MCInstLower                   │
│                                   MCCodeEmitter                 │
└─────────────────────────────────────────────────────────────────┘
```

Current status:

- `backend/c28x-mir` has produced C28x assembly/object code for selected
  `crates/rust-api` functions and passed RAM/JTAG hardware checks.
- `app/src/main.rs` is a one-file application pilot included by `crates/rust-api`.
  The `one-file-main` feature keeps it separate from the existing
  `crates/rust-api/src/user_main.rs`. The strict MIR gate accepts selected
  16-bit arithmetic, comparisons, branches, loops, returns, and Safe HAL GPIO
  calls. RAM/JTAG confirms the exact computed return value and GPIO30/GPIO34
  states. Unsupported MIR is rejected. The normal build compiles the restored
  C bridge source and links the default Timer0 callback; see
  `ONE_FILE_MAIN.md`.
- The same one-file source also has a separate build-only Flash link path.
  It reuses the verified Rust/C objects, adds a Flash-only `ramfuncs` copy and
  `InitFlash()` step, and audits Flash load segments and the Boot-ROM entry.
  RAM/JTAG remains the default; Flash programming and power-cycle proof are
  separate explicit hardware steps, not implied by a successful build.
- A separate RAM-only ownership pilot now lowers one Rust
  `AtomicU16::compare_exchange(0, 1)` method body and a Safe Rust caller for
  two RAM resources, followed by a pilot safe Rust GPIO34 `set_low` method.
  JTAG confirms first-success and second-failure for both resources and GPIO34
  output low. These are pilot types, not the existing Safe HAL path; see
  `OWNERSHIP_ONCE_RAM.md`.
- Verified examples include GPIO low/output cases, the MIR control loop,
  independent ADC/ePWM/Timer0 Safe HAL cases, GPIO34 output, GPIO39 low, and a
  RAM-only GPIO sweep harness.
- `gpio_output_readback_basic` now keeps the readback assertion in Safe Rust:
  `OutputPin::is_high/is_low` is recognized by the MIR backend and lowered into
  GPIO34 `GPBDAT` checks before the C harness records its final JTAG snapshot.
- The GPIO sweep currently proves GPIO0..34 and GPIO39..44 under JTAG.  GPIO35
  through GPIO38 are JTAG pins on this setup; strict all-45 physical pin freedom
  is not claimed while the debugger is attached.
- `backend/llvm-c28x` remains the long-term backend skeleton, not the current
  production path.

## PATH 2A: How the current MIR backend works

### 1. PAC layer (`crates/rust-api/src/pac.rs`)

The PAC defines a trait `MmioBus` with three operations:

```rust
trait MmioBus {
    fn write_word(&mut self, addr: u16, val: u16);
    fn read_word(&mut self, addr: u16) -> u16;
    fn modify(&mut self, addr: u16, mask: u16, bits: u16);
}
```

Two implementations:
- `HostMmio` (cfg(test)) — a HashMap-based fake for host unit tests
- `C28xMmio` (cfg(not(test))) — volatile pointer reads/writes

Typed register wrappers (`OutputConfig`, `UpCountConfig`, etc.) call these
methods with **compile-time constant addresses**.

### 2. The MIR analyzer (`backend/c28x-mir/src/main.rs`)

The analyzer runs as a `rustc_driver` callback.  For each function in the
crate, it walks the MIR and classifies what kind of function it is:

| Classifier | Recognizes | Emits |
|---|---|---|
| `classify_platform_control_loop` | The main control loop shape (20 f28035_* calls) | Inline MMIO + LCR to typed apply |
| `classify_mmio_write_sequence` | Straight-line `write_word` / `modify` / `write_u32` calls | XAR-indirect C28x stores |
| `classify_interrupt_callback` | Timer0 ISR pattern | PIE ack + clear eoc |
| `classify_safe_hal_adc_sample_basic` | `system_init` + `Peripherals::take` + one ADC sample call | ADC SOC0 sample sequence |
| `classify_safe_hal_epwm_compare_basic` | `system_init` + `Peripherals::take` + ePWM configure/set_compare | ePWM1A period/CMPA setup |
| `classify_safe_hal_timer0_periodic_basic` | `system_init` + `Peripherals::take` + Timer0 periodic start | Timer0 vector/periodic interrupt setup |
| `Max` / `Min` | Control loop arithmetic | CMP + conditional branch |

### 3. MMIO lowering variants

The backend recognizes five MMIO patterns:

| Variant | MIR shape | Generated asm |
|---|---|---|
| `Imm` | `write_word(bus, const_addr, const_val)` | `MOVL XAR4,#addr; MOVB AL,#val; MOV *XAR4,AL` |
| `Acc` | `write_word(bus, const_addr, val_from_arg)` | `POP ACC; MOVL XAR4,#addr; MOV *XAR4,AL` |
| `Modify` | `addr.modify(bus, mask, bits)` | `MOV AL,*XAR4; AND/OR; MOV *XAR4,AL` |
| `WriteU32` | `Register32::write_u32(bus, val)` | `MOV *XAR4,AL; MOV *+XAR4[1],AH` |
| `ReadIndirect` | `read_word(bus, runtime_addr)` | `MOV AL,*XAR4` |

**Key insight**: rustc's `-Zmir-opt-level=4` propagates the `TiWordAddress(26624_u16)`
constant into the call operand, so the backend can extract the physical
address directly without needing a general constant folder.

### 4. XAR indirect addressing (critical hardware lesson)

Early attempts used `MOVW DP, #page; MOV @offset, AL` — this failed on real
silicon because the TI assembler resolves `@0x00` to absolute address 0,
not DP-relative.  The working approach is **XAR indirect addressing**:

```asm
MOVL XAR4, #0x6805    ; absolute 22-bit address
MOV *XAR4, AL         ; indirect store
```

This bypasses DP entirely and works reliably.

### 5. EALLOW/EDIS auto-wrap

If any MMIO step touches an address in `0x7000-0x70FF` (SysCtrl/GpioCtrl/PieCtrl),
the backend automatically wraps the sequence in `EALLOW`/`EDIS`.

## PATH 2B: The LLVM backend skeleton

The `backend/llvm-c28x/` directory is a from-scratch LLVM backend, modeled after
MSP430.  It has:

- **24 registers** (ACC/AL/AH/XAR0-7/XT/SP/DP/ST0/ST1)
- **35 instructions** (MOV/ADD/SUB/AND/OR/XOR/LSL/LSR/SEXT/ZEXT/TRUNC/B/LCR/PUSH/POP)
- **Full pass pipeline** (ISelDAGToDAG → RegAlloc → FrameLowering → MCInstLower → AsmPrinter → MCCodeEmitter)

To build it:

```bash
cd backend/llvm-c28x
./bootstrap.sh
```

This clones LLVM, builds llvm-tblgen, runs TableGen to generate `.inc` files,
and builds `llc`.

## The gap between PATH 2A and PATH 2B

PATH 2A works today as a pattern-based MIR backend.  It handles the Rust shapes
that have explicit classifiers: selected arithmetic, call chains, GPIO Safe HAL
templates, interrupt callbacks, platform control-loop templates, and typed MMIO
write/read sequences.  It still cannot compile arbitrary Rust control flow,
generic data structures, panics, formatting, allocation, or the full `core`
surface.

The ADC/ePWM/Timer0 single-case bridge is now classified by Safe HAL call shape
rather than only by exported function name: the classifier requires system
initialization, the peripheral ownership take, and exactly the relevant ADC
sample / ePWM configure+compare / Timer0 periodic-start operation.  This is the
current stepping stone between case-specific templates and a fuller MSP430-style
backend.

PATH 2B is the route toward a general backend, but needs:

1. Real TableGen (not our Python stub)
2. Real ISelLowering patterns
3. LLVM backend compiled into rustc
4. core library ported to C28x

The `backend/llvm-c28x/rustc-patches/` directory has ready-to-use patches for steps 3-4.

## Hardware Verification

The project uses XDS100 via TI DSS/CCS scripts.  Current verified MIR-track
hardware evidence includes:

```powershell
.\tools\flash-and-verify-mir-control-loop.ps1 -SkipBuild
.\tools\verify-mir-gpio-sweep.ps1 -SkipBuild -AllowJtagPins
```

The control-loop verifier (`tools/verify-mir-control-loop.js`) reads:
- `AdcResult0` ≈ 2926
- `CMPA` ≈ ADC value
- `TBPRD` = 4095
- `tracking_error` = 0

The GPIO sweep verifier prints a per-pin table:

- strict GPIO0..44 mode intentionally fails while JTAG occupies GPIO35..GPIO38;
- `-AllowJtagPins` mode passes GPIO0..34 and GPIO39..44, with MUX/DIR and
  low/high readback recorded.
