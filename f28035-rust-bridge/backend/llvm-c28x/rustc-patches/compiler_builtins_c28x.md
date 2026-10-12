# compiler_builtins plan for C28x

The frozen Rust ABI uses 32-bit logical byte pointers on a 16-bit
word-addressed C28x machine:

```text
physical_word = logical_byte >> 1
byte_lane     = logical_byte & 1
```

Therefore the first production `compiler_builtins` port must implement memory
intrinsics in logical bytes, not raw C28x words.

## Required symbols

- `memcpy`
- `memmove`
- `memset`
- `memcmp`
- `__aeabi_memcpy` aliases are not required for `c28x-none-elf`; keep the
  surface small unless rustc or LLVM starts emitting them.

## Memory rules

- `memcpy(dst, src, n)` copies exactly `n` logical 8-bit bytes.
- Odd source and destination logical addresses are valid.
- Two adjacent logical bytes share one physical C28x word.
- Writes to one logical byte must preserve the other lane in that physical
  word.
- `memmove` must handle overlap in both directions.
- `memset` writes the low 8 bits of `c` into each logical byte.
- `memcmp` compares logical bytes in ascending address order.

## Bring-up order

1. Implement and test a C/Rust host model using `c28x-memory-model`.
2. Port that model to C28x assembly or backend-builtins IR.
3. Verify against hardware for:
   - zero length;
   - odd/even source and destination parity;
   - one-byte, two-byte, and multiword ranges;
   - forward and backward overlap for `memmove`;
   - lane preservation at both ends of a range.
4. Only then wire the implementation into `compiler_builtins`.

The old `memcpy_c28x.asm` file is a word-copy calling-convention sketch only;
it must not be installed as Rust's `memcpy`.
