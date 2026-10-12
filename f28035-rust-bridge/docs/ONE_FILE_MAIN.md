# One-file Rust application pilot

Edit `app/src/main.rs` and run from the repository root:

```powershell
& tools/run-user-main.ps1
& tools/run-user-main.ps1 -Verify
& tools/verify-user-main-reject.ps1
```

The RAM route above remains the default and never programs Flash. To build a
separate persistent image from the same `app/src/main.rs` without touching the
board, run:

```powershell
& tools/build-user-main-flash.ps1
```

This first rebuilds the RAM reference, then links
`build/user-main-flash/user_main_flash.out` into Flash sector A with
`codestart` at the Boot-ROM Flash entry. The Flash-only harness copies TI's
`ramfuncs` into RAM and runs `InitFlash()` before calling the Rust entry.
The build rejects loadable segments outside sector A and the two-word boot
entry, including the CSM password area.

Programming is a separate, destructive operation. It erases Flash sector A,
so first confirm that replacing the current image is intended and that the
GPIO34/GPIO37 boot straps select boot-to-Flash. The command requires an
explicit switch, rebuilds and audits the image, saves a full user-Flash
backup, checks erased/unprotected CSM state, programs with CCS
`Erase, Program, Verify`, then verifies a Boot-ROM reset without forcing PC:

```powershell
& tools/program-user-main-flash.ps1 -ConfirmFlashErase
```

The backup defaults to `backups/user-flash-before-<timestamp>.bin` and must
contain all 0x10000 user-Flash words before programming begins. A custom
location can be supplied with `-BackupFile`.

After physically removing and restoring power, verify persistence without
programming or loading any code (the `.out` is used for symbols only):

```powershell
& tools/verify-user-main-flash.ps1
```

The Flash verifier currently checks the GPIO30/GPIO34 sample and return value
`0xFFFD`. If the application behavior changes, update both the RAM and Flash
verifiers. A build-only PASS is not a claim that Flash programming or cold boot
has passed on hardware.

This route selects the `one-file-main` feature. The separate
`crates/rust-api/src/user_main.rs` remains untouched and is not compiled by
this command.

The normal build compiles `sdk/c-abi/f28035_bridge.c` from source and links
the project's default Timer0 callback. A diagnostic `-BridgeObject` override
can select a prebuilt object, but it does not validate the current C source.

The first command runs host Rust tests, type/borrow-checks the application via
rustc MIR, lowers the supported `rust_user_main` body to C28x assembly, and
links `build/user-main/user_main_ram.out` with the TI compiler and the C ABI
bridge and default interrupt callback. It checks the linked image's loadable
segments for flash and CSM
password-area overlap. `-Verify` loads this RAM image over XDS100 and checks
the current example's GPIO30/GPIO34 MUX, direction, and data snapshots. It
does not program flash. The C harness and startup are project infrastructure;
application authors edit only `app/src/main.rs`.

The current `rust_user_main` backend gate accepts scalar `u16`/`bool` locals,
`Add`, `Sub`, `Mul`, `BitAnd`, `BitOr`, `BitXor`, unsigned comparisons, and
`bool -> u16`, plus basic-block branches, loops, a `u16` return value, and
0-2 scalar-argument `f28035_*` calls in the PAC/FFI layer. The example
configures GPIO30 and GPIO34 as outputs, runs a five-iteration loop, reads
GPIO30, then calculates and returns `0xFFFD`; an unsigned comparison also
sets GPIO34 high. The C harness and JTAG verifier read the exact return
value. Calls go through the Rust API in `crates/rust-api`, then the existing
narrow C ABI. The separate `sdk/f28035-safe-hal` crate is not yet the input
to this pilot.

This is **not** a general Rust compiler. Heap allocation, arbitrary Rust
types/operators, callbacks, interrupts, and unvalidated peripheral calls do
not lower through this gate yet. An unsupported MIR shape fails the build; it
is not silently reduced to a list of C calls. The rejection command checks
this with unsupported atomic and division fixtures. If the application's pins
or expected output change, adapt the example-specific JTAG assertions in
`user_main_test.c` and
`verify-user-main.js`; the build command itself still only reads `main.rs`.
