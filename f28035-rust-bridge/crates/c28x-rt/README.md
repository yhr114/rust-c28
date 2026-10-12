# c28x-rt

Minimal runtime / startup for TI C2000 (C28x) microcontrollers, modeled after
[`msp430-rt`](https://github.com/rust-embedded/msp430-rt).

## Status

This crate is a **skeleton** adapted from the MSP430 Rust ecosystem.  It
documents the structure a real C28x Rust runtime should have, but cannot yet
build because Rust has no C28x LLVM backend.

When a backend becomes available (e.g. by forking the MSP430 LLVM backend),
this crate provides the rest: startup, linker script, vector table, and
`#[entry]` macro.

## Files

| File | Purpose |
|---|---|
| `c28x-none-elf.json` | Rust target spec (照 msp430.json 改) |
| `asm.s` | Reset handler: set SP, zero .bss, copy .data, call main |
| `memory.x` | F28035 memory map (RAMM0/M1/L2/L3, Flash A-H, VECTORS) |
| `link.x.in` | GNU ld linker script template (sections + ASSERTs) |
| `build.rs` | Copies linker scripts to OUT_DIR |
| `src/lib.rs` | Vector table, DefaultHandler, heap_start, entry |
| `examples/blinky.rs` | Usage example |

## Build (future)

```bash
cargo build --target c28x-none-elf \
    -Zbuild-std=core \
    -Zbuild-std-features=panic_immediate_abort \
    --example blinky
```

Linker flags (via `.cargo/config.toml`):
```toml
[target.'cfg(target_arch = "c28x")']
rustflags = [
    "-C", "linker=cl2000",
    "-C", "link-arg=-nostartfiles",
    "-C", "link-arg=-Tlink.x",
]
```

## Key differences from MSP430

| 项 | MSP430 | C28x |
|---|---|---|
| Stack top | top of RAM | top of RAMM0 (0x0400) |
| Reset vector | 0xFFFE | 0x3FFFC0 |
| Vector table | Flash end | Boot ROM (0x3FFFC2) |
| Interrupt return | RETI | LRETR + PIE ack |
| Linker | msp430-elf-gcc (GNU ld) | cl2000 (TI) |
| Data width | 16-bit word | 16-bit word (32-bit via two words) |

## PIE Vector Table

The C28x has a **second** interrupt table in RAM (`PIE VECTORS` at 0x0D00).
The CPU vectors (in Boot ROM) point to the PIE table entries.  The startup
code must:
1. Copy the CPU vector table from Flash to PIE RAM (or let Boot ROM do it)
2. User interrupt handlers are registered in PIE RAM, not directly in Flash.

This is not yet implemented in `asm.s`; it will require a PIE table copy
step after `.data` init.
