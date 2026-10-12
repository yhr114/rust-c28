# C28x Rust ownership method RAM pilot

This is a zero-C, RAM-only path-2 experiment. `crates/ownership-gpio34`
defines one reusable Rust method, `Once::rust_once_acquire(&self) -> u16`.
Its optimized MIR contains `AtomicU16::compare_exchange(0, 1, SeqCst,
SeqCst)`, a success check, and a `u16` result. A Safe Rust application
`rust_ownership_application` calls `Peripherals::take()` twice and
`Gpio::claim34()` twice; both wrapper methods are inlined into the optimized
MIR. Its first claimed handle then calls a safe Rust
`OutputPin34::rust_gpio34_set_low(&mut self)` method. The backend lowers that
caller's calls and success/failure branches, the reusable acquisition method,
and the pilot GPIO method's volatile register actions. Two RAM words represent the
peripheral-root and GPIO34 claims. The startup assembly only initializes
them, calls the Rust application, and records its `u16` return value.

Run from the repository root:

```powershell
& tools/verify-ownership-once-ram.ps1
& tools/verify-ownership-reject.ps1
```

Expected JTAG observations are `APPLICATION_RESULT=1`,
`OWNER_FLAGS=1,1`, GPIO34 `MUX=0`, `DIR=1`, `DATA=0`, and
`RUST_ONCE_METHOD_RAM=PASS`. Three negative tests change the Rust
compare-exchange expected value, reverse the application's second-take
branch, or replace the GPIO clear mask; the backend must reject all changed
MIR shapes.
The link map must contain only `ownership.obj` and `start.obj`, with no C
object or runtime library.

## Boundary

- Both the method body and a Safe Rust caller are lowered from optimized MIR
  and executed on F28035. The backend still recognizes their exact patterns;
  this is not generic Rust control-flow or atomic code generation.
- The pilot's `Peripherals::take`, `Gpio::claim34`, and GPIO output method are
  small local types in `crates/ownership-gpio34`, not the production implementations in
  `sdk/f28035-safe-hal`. The latter still do not execute on target in the
  existing zero-C GPIO34 image.
- The generated application passes the two RAM-word addresses in XAR4 to
  the generated acquisition method. Startup still initializes the words and
  records the application result in assembly.
- Startup sets INTM before any call and never enables interrupts. The emitted
  read/conditional-write implements this single-core RAM pilot only; it is
  not a general interrupt-safe `SeqCst` implementation.
- TI assembler/linker and XDS100/DSS remain the build and verification tools;
  flash is untouched.

Next target gate: replace the pilot wrappers and GPIO method with the existing
Safe HAL's `Peripherals::take`, `Gpio::claim`, output configuration, and
`set_low` path in the same zero-C image.
