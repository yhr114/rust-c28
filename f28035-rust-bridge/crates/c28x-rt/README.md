# c28x-rt — F28035 B-1 RAM runtime

The runtime now uses the TI linker, the built-in C28x target and the compiler's
`c28x-interrupt` ABI. The canonical workflow and current acceptance status are
in the main repository's `docs/PATH_B.md`. Flash boot and nested interrupts are
not covered by this RAM profile.

An application directly depends on this crate, uses the B-1 shared Cargo build
script, and sets `"rustRuntime": true` in `c28x-link.json`. Do not add a C main,
startup assembly or linkerCommands a second time. `build.rs` exports a TI RAM
command file through Cargo links metadata; the shared application build script
registers its inputs and passes that exact runtime manifest to the linker.
It no longer generates or searches for GNU memory.x/link.x/device.x.

```rust,ignore
#![no_std]
#![no_main]
#![feature(abi_c28x_interrupt)]

#[unsafe(export_name="PreInit")]
unsafe extern "C" fn early() { /* Operations valid before RAM initialization. */ }

#[unsafe(export_name="main")]
pub extern "C" fn boot() -> ! {
    // Configure peripheral, PIE mask and CPU IER before enabling interrupts.
    loop {}
}

#[no_mangle]
extern "c28x-interrupt" fn TINT0() {
    // Handle Timer0, clear its TIF flag and acknowledge PIE group 1.
}
```

These are Rust functions; `extern "C"` specifies the calling convention and
does not require a C source file. This direct-export form is the tested Cargo
workflow on active `20261027-171858-19176840-af788b4d`. Run B-1
`tools/verify-cargo-runtime.ps1` for direct exports, macro exports, signature
rejection and RAM/JTAG acceptance. Package location and hashes are in PATH_B §4.

The optional `macros` feature provides `entry`, `pre_init` and `interrupt`.
The active bundle includes matching host `std` and `proc_macro`. A Cargo
application using all three macros passed the same hardware test, and nine
invalid signatures/calls were rejected. Enable it with
`c28x-rt = { path = ".../c28x-rt", features = ["macros"] }`.
The macros reject arguments, generics, async/const or pre-existing ABI modifiers.
Entry must return `!`; pre_init must be unsafe and return unit; an interrupt
returns unit or `!` and must name an actual F28035 vector. They export C `main`,
C `PreInit` and an `extern "c28x-interrupt"` handler respectively. The compiler
performs the interrupt software context save and IRET; do not wrap it in the
legacy C-handler trampoline from `interrupts.s`.

`asm.s` owns the single native-address PIE table: 128 slots (32 CPU/reserved plus
12 groups of 8). Undefined weak handlers are replaced by DefaultHandler while
copying into PIE RAM. The first three Boot ROM/emulation slots remain untouched.
Timer0 is index 38 at TI word address 0x0D4C. Rust logical function pointers must
not be written directly as hardware vector addresses.

Startup masks interrupts, sets SP/OBJMODE, disables watchdog, sets the existing
60 MHz board clock profile, calls the optional weak PreInit, initializes vectors,
clears BSS and copies data with zero-length guards, calls TI __TI_auto_init,
then calls the Rust entry. DefaultHandler is a weak non-returning assembly sink.
The minimal assembly and TI initializer remain part of the runtime; application
entry and interrupt bodies require no C driver.

Files: `asm.s` (startup/vectors/CPU helper leaves), `ram.cmd` (TI RAM placement),
`build.rs` (Cargo runtime metadata), `src/lib.rs` (Rust API/re-exported macros).
The old `memory.x`/`link.x.in` are unused legacy references. The complete sample
is B-1 `crates/c28x-cargo-runtime`; its register-sentinel assembly is test-only.

## Safe shared state (B-1)

`SharedCell<T>` checks exclusive access before creating `&mut T`. Use
`CELL.try_with(|value| ...)` to handle `SharedCellBorrowError` on reentry or host
thread contention; `CELL.with(...)` and `CELL.replace(...)` panic on conflict.
The conflicting callback is never called, and the outer borrow remains held.
Host access uses an acquire/release atomic lock, without spinning or poisoning.
Unwinding releases the borrow; firmware built with `panic=abort` stops on panic.
The target borrow flag uses explicit volatile 16-bit accesses to preserve the
C28x native access width; interrupt masking provides exclusion, not volatile.

```rust
use c28x_rt::SharedCell;
static COUNT: SharedCell<u32> = SharedCell::new(0);
COUNT.with(|value| *value = value.wrapping_add(1));
let snapshot = COUNT.try_with(|value| *value).unwrap();
assert_eq!(snapshot, 1);
```

`critical_section(|| { ... })` masks C28x interrupts and restores the previous
INTM state when the callback returns. This replaces the old public guard API;
callers cannot forget the guard, drop nested guards out of order, or move them
to another thread. On hosts this closure alone does not synchronize threads;
`SharedCell` has its own lock. NMI and DMA are outside the INTM protection model.

The assembly helper reads the single saved ST1 word with `MOV AL,*--SP` and
masks **bit 0** (INTM), following the TI `DSP2803x_DisInt.asm` stack convention.
The B-1 runtime regression also checks reentry rejection, actual ST1 restoration,
stack balance and shared updates from the main loop and Timer0 handler.
Direct and macro entry variants passed all 12 shared-state checks and 48 Timer0
interrupts each on active `20261028-162823-7a7c48fc-ee53e7b7`. Evidence is in B-1
`build/shared-cell-runtime-20261028-r4/`. The runtime verifier also runs the
7 host tests and 2 compile-fail tests via `tools/verify-shared-cell-host.ps1`.
