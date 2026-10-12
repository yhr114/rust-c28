# C28x rustc direct object path

Pinned compiler: `nightly-2026-09-14`, Rust commit
`4b6d04e706108ccfeafe2547fbe857dfe8972bad`, LLVM 23.1.1.
The frozen logical-byte data layout is
`e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16`.
See `ABI_FREEZE.md` for the pointer and TI-word assumptions.

## Verified on 2026-09-30

- `tools/check-rustc-patch.ps1`: the patch applies to the pinned rustc source.
- `tools/verify-rustc-c28x-object.ps1`: stage1 `rustc` reads a Rust source file,
  emits C28x LLVM IR and an EABI ELF `.obj`, and TI `cl2000` links that object
  with a TI-compiled C caller.
- `tools/verify-cargo-c28x-object.ps1`: Cargo drives the same patched `rustc` and
  emits a C28x `.o`; TI tools recognize and link it with a C caller.
- `tools/verify-rustc-c28x-hal-metadata.ps1`: the C28x target type-checks
  `core`, `compiler_builtins`, `sdk/f28035-safe-hal`, and `example/case1/src/main.rs`
  using metadata-only output. This does not generate executable HAL code.

These are compile/link checks, not a hardware execution test. The linked C
caller proves symbol resolution, not the runtime calling convention.

## Current code generation blocker

`cargo build -Zbuild-std=core --target c28x-none-elf` reaches target `core`
generation but LLVM cannot select a store of `i8` to a stack frame index
(first observed in `core/src/cmp.rs:672`). The backend needs a correct mapping
between 8-bit Rust values, 32-bit logical-byte pointers, and C28x 16-bit
physical words. Widening an `i8` store to a whole word without accounting for
its byte lane could corrupt adjacent data. Until that mapping is implemented
and verified, Safe HAL and `case1` cannot be emitted as complete C28x objects.

Other backend operations, `core` intrinsics, interrupt ABI, final firmware
startup, and board behavior remain unverified.

## Patch contents

`rustc-patches/0001-add-c28x-target.patch` changes five rustc files:

1. Adds the built-in `c28x-none-elf` target spec.
2. Registers it in `rustc_target`.
3. Adds C28x to `rustc_llvm`'s optional LLVM components.
4. Calls the C28x LLVM target and assembly-printer initializers at startup.
5. Adds a provisional scalar `extern "C"` ABI path. Aggregate and variadic
   compatibility with TI C has not been established.

The target uses `Arch::Other("c28x".into())`; it does not add a new `Arch`
enum variant. This avoids unrelated exhaustive-match changes in rustc.

## Local compiler build

The current working stage1 compiler is at
`D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe`.
The Rust source is at
`D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad`.
Its `src/llvm-project` points to the patched LLVM 23.1.1 source with the
C28x backend. The checked-in `rustc-patches/bootstrap-windows-gnu.toml`
is copied to `bootstrap.toml` if that file is absent. It builds the GNU Windows host with
LLVM `X86` and experimental `C28x`, uses llvm-mingw `clang++` and libc++, and
keeps `build.target` host-only. Adding `c28x-none-elf` to `build.target` in
this bootstrap configuration makes cc-rs try to find a C cross compiler
before the stage1 compiler is available.

To rebuild the current compiler with the working local environment:

```powershell
powershell -File tools/build-rustc-c28x.ps1
powershell -File tools/build-rustc-c28x.ps1 -BuildHostStd
```

The script sets the GNU nightly, LLVM/UCRT runtime, MinGW linker paths,
and a separate temporary directory. It uses two parallel jobs by default;
use `-Jobs 1` if memory or disk space is tight. The second command supplies host-side
`std` for Cargo build scripts.
The patch check uses the original `rustc-src` component and `git apply --check`:

```powershell
powershell -File tools/check-rustc-patch.ps1
```

`tools/prepare-rustc-c28x.ps1` can apply the target patch and copy this
bootstrap template into a Git checkout. Its clone and submodule steps still
depend on network access and should be checked against the pinned Rust/LLVM
revisions before creating a fresh compiler tree.
