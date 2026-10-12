# Proposed Rust ABI for C28x

Status: experimental executable specification. It is not yet a stable ABI.
The four scalar packed-byte primitives (low/high read and low/high
read-modify-write) passed an XDS100/F28035 target test on 2026-09-14.
The first physical-word-pointer runtime also passed: offsets 0..3 over words
`[0x2211, 0x4433]` returned `[0x11, 0x22, 0x33, 0x44]`, and writes at offsets
0 and 3 preserved their adjacent lanes.
Host tests now exhaust all 65,536 input word values for extraction and all 256
byte values for replacement in both lanes. The F28035 also executes all 256
replacement values in each lane, checking read-back and adjacent-lane
preservation on every iteration.
The safe reference layer now includes a lifetime-bound `PackedBytes<'a>` view
with checked byte and little-endian `u16` access, including unaligned `u16`
operations that cross a physical-word boundary.

## Goals

- Preserve Rust's 8-bit `u8`/`i8` values and byte-oriented layouts.
- Pack two logical Rust bytes into one 16-bit-addressable C28x data word.
- Keep aligned `u16` objects in one C28x word and aligned `u32` objects in two.
- Keep MMIO word addresses distinct from ordinary Rust logical byte addresses.
- Interoperate with TI EABI through explicit scalar and pointer bridges.

## Logical addresses

Ordinary Rust pointers contain a 32-bit logical byte address. Translation to a
C28x physical word address is:

```text
word_address = logical_byte_address >> 1
byte_lane    = logical_byte_address & 1
```

Lane zero is bits 7..0. Lane one is bits 15..8. Therefore the logical byte
sequence `[0x11, 0x22, 0x33, 0x44]` has the physical representation
`[0x2211, 0x4433]`.

Pointer arithmetic is performed in logical bytes before address translation.
Linker symbols and TI C pointers contain physical word addresses and must not
be used as ordinary Rust pointers without an explicit conversion.

## Scalar layout

| Rust type | Logical size | Logical alignment | Physical storage when aligned |
|---|---:|---:|---:|
| `u8`/`i8` | 1 byte | 1 byte | half of one C28x word |
| `u16`/`i16` | 2 bytes | 2 bytes | one C28x word |
| `u32`/`i32`/`f32` | 4 bytes | 4 bytes | two C28x words |
| pointer/`usize`/`isize` | 4 bytes | 4 bytes | two C28x words |

The exact `u32`, `f32`, aggregate, and return-value ordering still requires TI
EABI comparison tests before being frozen.

## Byte loads and stores

A byte load reads one physical word and selects a lane. A byte store performs
a read-modify-write so the adjacent logical byte is preserved. Word-copy fast
paths may be used only when source address, destination address, and length are
all suitably aligned.

Packed byte read-modify-write is forbidden for MMIO registers. PAC register
types use physical `WordAddress` values and explicit 16-bit or 32-bit volatile
accesses instead of ordinary byte pointers.

## TI EABI boundary

The currently verified scalar convention is:

```text
first u16 argument  -> AL
second u16 argument -> AH
u16 return value    -> AL
```

TI C `char` is 16 bits and is not ABI-compatible with Rust `u8`. Ordinary Rust
pointers are logical byte addresses and are not ABI-compatible with TI C word
pointers. FFI must use audited scalar values, `TiWordAddress`, or a bridge that
converts addresses and lengths explicitly.

## Required validation before stabilization

- compiler lowering from ordinary Rust pointers to the verified packed-byte
  pointer runtime (the TI word-pointer runtime itself is verified);
- adjacent-byte preservation;
- aligned and unaligned `u16` access;
- `u32` word ordering and calling convention;
- arrays, structures, enums, slices, and pointer arithmetic;
- `memcpy`, `memmove`, `memset`, and `memcmp` for every address parity;
- volatile MMIO access kept outside the packed byte path;
- target tests for zero, maximum values, overlap, and end-of-buffer behavior.
