# Zero-C RAM GPIO experiment

This is a RAM-only C28x compiler experiment. Both images link only MIR-derived
Rust assembly and a minimal startup assembly object. No C object or TI C
runtime library is linked, and the verifier does not program flash.

## Reproduce

From the repository root:

```powershell
& tools/verify-zero-c-gpio-ram.ps1
& tools/verify-zero-c-gpio-ram.ps1 -SafeHal
& tools/verify-bare-mmio-reject.ps1
```

The first image uses `crates/bare-gpio34/src/lib.rs`. Its optimized Rust MIR
contains constant physical-word `read`, bitwise modify, and `write` operations.
`backend/c28x-mir` lowers the complete straight-line sequence, including
GPIO2 and GPIO34 configuration, GPIO34 high/low commands, and repeated
configuration. The JTAG verifier first places both pins high and changes their
MUX and direction, then requires both to be GPIO outputs reading low and the
CPU to be at `bare_idle`.

The second image starts at `rust_safe_gpio34_low` in the existing
`sdk/f28035-safe-hal` crate. Its Rust source calls `Peripherals::take`,
`Gpio::output::<34>`, and `OutputPin::set_low`. rustc type-checks this code;
the MIR backend checks the call pattern and emits the corresponding GPIO34
register instructions. The JTAG verifier checks GPIO34 MUX, direction, data,
and idle PC. This is a typed Safe HAL **entry** in a zero-C image, but the
backend still replaces the HAL call chain with a recognized sequence rather
than compiling the HAL implementation generically.

The rejection check confirms that a branching raw-MMIO body and a changed
Safe HAL `set_high` action both fail lowering. The build scripts also reject
external references in generated assembly and libraries/C objects in the map.

## Current boundary

- `WordAddress` uses a physical C28x word address. Its Rust volatile-pointer
  method bodies are not generically lowered; the accepted MIR sequence is
  lowered by this out-of-tree backend.
- The Safe HAL image does not yet execute `Peripherals::take` ownership state
  or the ordinary `OutputPin` method bodies on target. Its one-shot entry is
  type-checked, then the backend emits equivalent GPIO register effects.
- All peripheral ownership handles now have private constructors and do not
  implement `Copy` or `Clone`; validated SPI/SCI/I2C result tokens remain
  copyable values with private constructors. Host `compile_fail` tests reject
  forged and duplicated handles. This source-level safety improvement does
  not prove that the ownership state machine runs in the zero-C image.
- The next target gate must execute two `take()` calls and a duplicate GPIO34
  claim from the actual HAL implementation, then verify the second take and
  claim fail while the first handle can still drive the pin low. The current
  GPIO34 pattern classifier cannot satisfy that gate.
- A separate zero-C RAM pilot now executes a reusable Rust `Once::acquire`
  method and a Safe Rust caller that checks first-success/second-failure for
  two ownership words, then invokes its own safe Rust GPIO34 `set_low` method
  on silicon. See `OWNERSHIP_ONCE_RAM.md`; it uses local pilot types, not yet
  the existing HAL's `take`, `claim`, or `set_low` methods.
- Startup, stack setup, and watchdog disable still come from a small C28x
  assembly file. CCS/XDS100 and TI assembler/linker remain build/debug tools.
- There is no general Rust ABI, arbitrary control flow, ISR/runtime, or full
  `core` support for the C28x target yet.

Recorded results: `BARE_GPIO_MULTI_RAM=PASS`,
`SAFE_HAL_GPIO34_ZERO_C_RAM=PASS`, `UNSUPPORTED_MMIO_REJECT=PASS`, and
`SAFE_HAL_ACTION_REJECT=PASS`.
